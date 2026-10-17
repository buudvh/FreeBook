import Foundation
import SwiftData

/// Tác vụ tải/xuất của sách **truyện tranh / video** — rẽ khỏi `executeTask` ngay sau khi đăng ký dọn dẹp, để
/// media không bao giờ chạm pipeline chữ (`ExportContentProvider`, `BookBinManager`, `ChapterContentRepository`).
///
/// - Comic + `.download`: tải **tuần tự** từng chương, từng ảnh (chủ ý, tránh bị nguồn chặn) vào `ComicOfflineStore`.
///   Bỏ qua chương đã có manifest **cùng URL chương** (khác URL ⇒ tải lại, ghi đè); tôn trọng `startFromCurrent` /
///   `limit`; tiến độ theo chương; huỷ được. Script ảnh chạy trên `ComicImageScriptRunner` riêng của tác vụ.
/// - Comic/video + xuất ebook, video + tải: báo thất bại (UI bình thường đã ẩn các nút này).
extension DownloadManager {
    /// `true` khi tác vụ thuộc sách media và đã được xử lý trọn ở đây — caller phải `return` ngay.
    internal func executeMediaTaskIfNeeded(
        _ task: DownloadTask,
        extensionSnapshot: Extension?,
        container: ModelContainer
    ) async -> Bool {
        let kind = ExtensionContentKind.resolve(packageId: task.extensionPackageId)
        guard kind.isMedia else { return false }

        if task.taskType.isExport {
            AppLogger.shared.log("❌ [DownloadManager] Từ chối xuất ebook cho sách \(kind.rawValue): \(task.bookTitle)")
            await markFailed(taskId: task.id, error: "Không hỗ trợ xuất ebook cho truyện tranh/video")
            return true
        }
        guard kind == .comic else {
            AppLogger.shared.log("❌ [DownloadManager] Từ chối tải offline sách \(kind.rawValue): \(task.bookTitle)")
            await markFailed(taskId: task.id, error: "Video không hỗ trợ tải offline")
            return true
        }

        await executeComicDownload(task, extensionSnapshot: extensionSnapshot, container: container)
        return true
    }

    // MARK: - Comic

    private func executeComicDownload(_ task: DownloadTask, extensionSnapshot: Extension?, container: ModelContainer) async {
        let taskId = task.id
        guard let ext = extensionSnapshot else {
            AppLogger.shared.log("❌ [DownloadManager] Tiện ích \(task.extensionPackageId) chưa cài, không tải được ảnh truyện tranh")
            await markFailed(taskId: taskId, error: "Tiện ích nguồn chưa được cài đặt.")
            return
        }

        let chapters: [StoredChapterSnapshot]
        do {
            chapters = try await comicChaptersToDownload(task, container: container)
        } catch {
            AppLogger.shared.log("❌ [DownloadManager] Không chuẩn bị được danh sách chương truyện tranh: \(error.localizedDescription)")
            await markFailed(taskId: taskId, error: error.localizedDescription)
            return
        }

        let total = chapters.count
        await updateProgress(taskId: taskId, progress: 0, total: total)
        // Runner riêng: không chung executor/lượt chạy với màn đọc (`ComicImageLoader.shared`), tự nhả khi xong/huỷ.
        let scriptRunner = ComicImageScriptRunner()

        var downloadedCount = 0
        var skippedCount = 0
        var failedCount = 0
        var lastErrorMessage: String?

        for (offset, chapter) in chapters.enumerated() {
            if await isComicTaskCancelled(taskId) {
                await finishCancelledComicDownload(taskId: taskId, scriptRunner: scriptRunner)
                return
            }

            let chapterUrl = JSExecutor.cleanAndResolveUrl(chapter.url, host: chapter.host)
            if ComicOfflineStore.manifest(bookId: task.bookId, chapterIndex: chapter.index)?.chapterUrl == chapterUrl {
                skippedCount += 1
            } else {
                do {
                    try await downloadComicChapter(
                        chapter,
                        chapterUrl: chapterUrl,
                        bookId: task.bookId,
                        ext: ext,
                        scriptRunner: scriptRunner
                    )
                    downloadedCount += 1
                } catch {
                    ComicOfflineStore.discardChapter(bookId: task.bookId, chapterIndex: chapter.index)
                    // Huỷ giữa chừng có thể nổi lên dưới dạng `URLError.cancelled`/lỗi JS chứ không chỉ `CancellationError`.
                    if error is CancellationError || Task.isCancelled {
                        await finishCancelledComicDownload(taskId: taskId, scriptRunner: scriptRunner)
                        return
                    }
                    failedCount += 1
                    lastErrorMessage = error.localizedDescription
                    AppLogger.shared.log("❌ [DownloadManager] Lỗi tải ảnh chương \(chapter.index) của \(task.bookTitle): \(error.localizedDescription)")
                }
            }

            await updateProgress(taskId: taskId, progress: offset + 1, total: total)
        }

        await scriptRunner.releaseAll()
        AppLogger.shared.log("📊 [DownloadManager] Tác vụ comic \(taskId) xong: tải \(downloadedCount), có sẵn \(skippedCount), lỗi \(failedCount)/\(total) chương")

        if failedCount > 0 {
            let detail = lastErrorMessage.map { " (\($0))" } ?? ""
            await markFailed(taskId: taskId, error: "Lỗi tải \(failedCount)/\(total) chương\(detail)")
        } else {
            await markCompleted(taskId: taskId)
        }
    }

    /// Một chương: `comicPages` → từng ảnh qua `ComicImageLoader.data(for:scriptRunner:)` → ghi đĩa → manifest sau cùng.
    /// `chapterUrl` là URL đã resolve mà vòng lặp dùng để so manifest — ghi đúng giá trị đó vào manifest mới.
    private func downloadComicChapter(
        _ chapter: StoredChapterSnapshot,
        chapterUrl: String,
        bookId: String,
        ext: Extension,
        scriptRunner: ComicImageScriptRunner
    ) async throws {
        let pages = try await ExtensionManager.shared.comicPages(
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            url: chapter.url,
            host: chapter.host,
            configJson: ext.configJson
        )
        guard !pages.isEmpty else {
            throw NSError(domain: "DownloadManager", code: -20, userInfo: [NSLocalizedDescriptionKey: "Chương không có ảnh nào."])
        }

        let directory = try ComicOfflineStore.prepareChapterDirectory(bookId: bookId, chapterIndex: chapter.index)
        var storedPages: [ComicChapterManifest.Page] = []
        storedPages.reserveCapacity(pages.count)

        for (pageOffset, source) in pages.enumerated() {
            try Task.checkCancellation()
            let request = ComicImageRequest(
                source: source,
                chapterUrl: chapterUrl,
                extensionLocalPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                configJson: ext.configJson
            )
            let data = try await ComicImageLoader.shared.data(for: request, scriptRunner: scriptRunner)
            let page = try ComicOfflineStore.writePage(
                data,
                pageNumber: pageOffset + 1,
                chapterDirectory: directory,
                knownWidth: source.width,
                knownHeight: source.height
            )
            storedPages.append(page)
        }

        try Task.checkCancellation()
        let manifest = ComicChapterManifest(chapterUrl: chapterUrl, pages: storedPages, completedAt: Date())
        try ComicOfflineStore.saveManifest(manifest, bookId: bookId, chapterIndex: chapter.index)
    }

    /// Mục lục cần tải — cùng quy tắc với nhánh chữ của `executeTask` (ChapterStore trước, SwiftData sau;
    /// `startFromCurrent` theo `currentChapterIndex`; `limit`), và cũng đẩy truyện lên kệ nếu chưa nằm ở đâu.
    private func comicChaptersToDownload(_ task: DownloadTask, container: ModelContainer) async throws -> [StoredChapterSnapshot] {
        let context = ModelContext(container)
        let allBooks = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        guard let book = allBooks.first(where: { $0.bookId == task.bookId }) else {
            throw NSError(domain: "DownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy truyện trong cơ sở dữ liệu."])
        }
        if !book.isOnShelf && !book.isHistory {
            book.isOnShelf = true
            try? context.save()
        }

        // Đọc hết từ `@Model` trước `await` (context không được dùng chéo luồng).
        let currentIndex = book.currentChapterIndex
        let legacyChapters = book.chapters.sorted(by: { $0.index < $1.index }).map { ch in
            StoredChapterSnapshot(
                id: ch.id,
                bookId: ch.bookId,
                title: ch.title,
                url: ch.url,
                index: ch.index,
                host: ch.host,
                titleTrans: ch.titleTrans,
                isCached: ch.isCached,
                offset: ch.offset,
                length: ch.length
            )
        }

        let storeChapters = (try? await ChapterStore.shared.fetchOrderedTOC(bookId: task.bookId)) ?? []
        let sortedChapters = storeChapters.isEmpty ? legacyChapters : storeChapters

        let startIdx = task.startFromCurrent ? currentIndex : 0
        guard startIdx >= 0, startIdx < sortedChapters.count else {
            throw NSError(domain: "DownloadManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Chỉ mục chương bắt đầu vượt quá số lượng chương hiện có."])
        }
        let endIdx = task.limit.limitValue.map { min(startIdx + $0, sortedChapters.count) } ?? sortedChapters.count
        return Array(sortedChapters[startIdx..<endIdx])
    }

    /// Huỷ qua `cancelTask`/`cancelTasksForBook`/`deleteTask` (đều `handle.cancel()`), cộng cờ `isTaskCancelled`.
    private func isComicTaskCancelled(_ taskId: UUID) async -> Bool {
        if Task.isCancelled { return true }
        return await MainActor.run { self.isTaskCancelled(taskId: taskId) }
    }

    private func finishCancelledComicDownload(taskId: UUID, scriptRunner: ComicImageScriptRunner) async {
        await scriptRunner.releaseAll()
        await markCancelled(taskId: taskId)
    }
}
