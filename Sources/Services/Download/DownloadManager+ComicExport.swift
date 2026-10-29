import Foundation
import SwiftData

/// Tác vụ **xuất truyện tranh** ra CBZ/PDF — rẽ từ `executeMediaTaskIfNeeded` (`DownloadManager+Comic`), không bao giờ
/// chạm pipeline chữ (`ExportRendererFactory`, `ExportContentProvider`).
///
/// - Phạm vi chương theo đúng luật của tác vụ tải ảnh (`comicChaptersToDownload`: chương bắt đầu, `limit`, bỏ dòng tiêu
///   đề nhóm) nhưng **chỉ** lấy chương đã có ảnh offline (manifest khớp URL chương, cùng cách so của màn đọc) — không
///   phát request mạng nào. Không có chương nào ⇒ "Thất bại" kèm lời nhắc tải ảnh trước, không tạo file rỗng.
/// - File ra `Documents/Exports/` qua `ExportFileNaming` như ebook; xong thì `markExportCompleted` mở share sheet. Thiếu
///   chương ⇒ dòng tổng kết "Đã xuất X/Y chương".
/// - Truyện tranh nhập từ file (`LocalMediaPackage`) có sẵn mọi ảnh nên xuất được trọn bộ.
extension DownloadManager {
    internal func executeComicExport(_ task: DownloadTask, format: BookExportFormat, container: ModelContainer) async {
        let taskId = task.id
        let planned: [StoredChapterSnapshot]
        let bookHost: String?
        do {
            let prepared = try await comicChaptersToDownload(task, container: container)
            planned = prepared.chapters
            bookHost = prepared.bookHost
        } catch {
            AppLogger.shared.log("❌ [DownloadManager] Không chuẩn bị được danh sách chương để xuất \(format.displayName): \(error.localizedDescription)")
            await markFailed(taskId: taskId, error: error.localizedDescription)
            return
        }

        let total = planned.count
        await updateProgress(taskId: taskId, progress: 0, total: total)
        await updateExportStage(taskId: taskId, stage: .fetchingChapters)

        var chapters: [ComicExportChapter] = []
        for (offset, chapter) in planned.enumerated() {
            guard let manifest = ComicOfflineStore.manifest(bookId: task.bookId, chapterIndex: chapter.index),
                  !manifest.pages.isEmpty,
                  Self.manifestMatches(manifest, chapter: chapter, bookHost: bookHost) else { continue }
            let pages = manifest.pages.map {
                ComicOfflineStore.pageFileURL(bookId: task.bookId, chapterIndex: chapter.index, file: $0.file)
            }
            chapters.append(ComicExportChapter(position: offset + 1, ordinal: chapters.count + 1, title: chapter.title, pages: pages))
        }
        guard !chapters.isEmpty else {
            AppLogger.shared.log("❌ [DownloadManager] Xuất \(format.displayName) '\(task.bookTitle)': không có chương nào đã tải ảnh (\(total) chương trong phạm vi)")
            await markFailed(taskId: taskId, error: "Chưa có chương nào đã tải ảnh offline trong phạm vi đã chọn — hãy tải ảnh trước khi xuất.")
            return
        }

        // Fail sớm trước khi ghi file `.part`: CBZ không có ZIP64 ⇒ tối đa 65.535 entry và 4 GB. Không chặn trước thì
        // truyện dài nhiều ảnh nhỏ chỉ báo lỗi sau khi đã ghi gần hết.
        if format == .cbz {
            let pageURLs = chapters.flatMap(\.pages)
            let totalBytes = pageURLs.reduce(Int64(0)) { sum, url in
                sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            if pageURLs.count >= Int(UInt16.max) || totalBytes >= Int64(UInt32.max) {
                AppLogger.shared.log("❌ [DownloadManager] Xuất CBZ '\(task.bookTitle)' vượt giới hạn ZIP: \(pageURLs.count) ảnh, \(totalBytes) byte")
                await markFailed(
                    taskId: taskId,
                    error: "Bản CBZ vượt giới hạn của định dạng ZIP (tối đa 65.535 ảnh, 4 GB) — hãy xuất ít chương hơn mỗi lần."
                )
                return
            }
        }

        await updateExportStage(taskId: taskId, stage: .renderingFile)
        // Tiến độ đẩy qua Task không chờ (PDF ghi đồng bộ) ⇒ một lượt trễ có thể tới **sau** khi tác vụ đã xong/thất bại;
        // `updateProgress` luôn đặt lại `.running` nên chỉ áp khi tác vụ còn đang chạy.
        let reportChapter: (ComicExportChapter) -> Void = { chapter in
            Task { @MainActor in
                guard self.tasks.first(where: { $0.id == taskId })?.status == .running else { return }
                self.updateProgress(taskId: taskId, progress: chapter.position, total: total)
            }
        }
        do {
            let target = try ExportFileNaming.targetURL(bookTitle: task.bookTitle, format: format)
            let fileURL: URL
            switch format {
            case .cbz:
                fileURL = try await ComicCbzExportWriter.write(
                    chapters: chapters,
                    to: target,
                    onChapterDone: { reportChapter($0) },
                    isCancelled: { await self.isComicTaskCancelled(taskId) }
                )
            case .pdf:
                let author = bookAuthor(bookId: task.bookId, container: container)
                fileURL = try ComicPdfExportWriter.write(
                    chapters: chapters,
                    title: task.bookTitle,
                    author: author,
                    to: target,
                    onChapterDone: reportChapter
                )
            default:
                throw ExportRenderError.unsupportedFormat(format.displayName)
            }
            if await isComicTaskCancelled(taskId) {
                try? FileManager.default.removeItem(at: fileURL)
                throw CancellationError()
            }

            let artifact = ExportArtifact(fileURL: fileURL, format: format, chapterCount: chapters.count)
            guard artifact.exists else { throw ExportRenderError.cannotCreateFile(fileURL.path) }
            await updateProgress(taskId: taskId, progress: total, total: total)
            let missing = total - chapters.count
            let pageCount = chapters.reduce(0) { $0 + $1.pages.count }
            AppLogger.shared.log("📊 [DownloadManager] Xuất \(format.displayName) '\(task.bookTitle)': \(chapters.count)/\(total) chương, \(pageCount) ảnh")
            let summary = missing > 0 ? "Đã xuất \(chapters.count)/\(total) chương — thiếu \(missing) chương chưa tải ảnh." : nil
            await markExportCompleted(taskId: taskId, artifact: artifact, summary: summary)
        } catch {
            if error is CancellationError || Task.isCancelled {
                await markCancelled(taskId: taskId)
                return
            }
            AppLogger.shared.log("❌ [DownloadManager] Lỗi xuất \(format.displayName) '\(task.bookTitle)': \(error.localizedDescription)")
            await markFailed(taskId: taskId, error: error.localizedDescription)
        }
    }

    /// Cùng hai cách so của `ComicReaderViewModel.offlinePages`: URL chương với host chương (công thức của bộ tải ảnh),
    /// hoặc với host chương → host sách.
    private static func manifestMatches(_ manifest: ComicChapterManifest, chapter: StoredChapterSnapshot, bookHost: String?) -> Bool {
        let chapterHost = chapter.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveHost = (chapterHost?.isEmpty == false) ? chapterHost : bookHost
        return manifest.chapterUrl == JSExecutor.cleanAndResolveUrl(chapter.url, host: chapter.host)
            || manifest.chapterUrl == JSExecutor.cleanAndResolveUrl(chapter.url, host: effectiveHost)
    }

    /// Tác giả cho metadata PDF; đọc bằng `ModelContext` riêng (tác vụ nền không dùng context của MainActor).
    private func bookAuthor(bookId: String, container: ModelContainer) -> String {
        let context = ModelContext(container)
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        return books.first(where: { $0.bookId == bookId })?.author ?? ""
    }
}
