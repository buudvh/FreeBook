import Foundation
import SwiftData
import UIKit

public enum ChapterLimitOption: Int, CaseIterable, Codable {
    case all = 0
    case fifty = 50
    case oneHundred = 100
    case twoHundred = 200
    case fiveHundred = 500
    case oneThousand = 1000

    public var title: String {
        switch self {
        case .all: return "Tất cả"
        default: return "\(self.rawValue) chương"
        }
    }

    public var limitValue: Int? {
        switch self {
        case .all: return nil
        default: return self.rawValue
        }
    }
}

public enum TaskType: String, Codable, Identifiable {
    case download = "Tải truyện"
    case exportTxt = "Xuất ebook TXT"
    public var id: String { self.rawValue }
}

public enum TaskStatus: String, Codable {
    case pending = "Đang chờ"
    case running = "Đang chạy"
    case completed = "Hoàn thành"
    case failed = "Thất bại"
    case cancelled = "Đã hủy"
}

public struct DownloadTask: Identifiable {
    public let id: UUID
    public let bookId: String
    public let bookTitle: String
    public let bookCoverUrl: String
    public let taskType: TaskType
    public var status: TaskStatus
    public var progressCount: Int
    public var totalCount: Int
    public var errorMessage: String?
    public var isCancelled: Bool = false

    public let extensionPackageId: String
    public let detailUrl: String
    public let startFromCurrent: Bool
    public let limit: ChapterLimitOption
    public let translate: Bool
    public let onlyExportCached: Bool
    public var exportFilePath: String? = nil
}

public final class DownloadManager: ObservableObject {
    public static let shared = DownloadManager()

    /// Khoảng coalesce `save()` của task store, tính bằng giây — xem `DownloadManager+TaskStore.swift`.
    internal static let taskSaveCoalesceInterval: CFAbsoluteTime = 1.0
    /// Khoảng phát `@Published tasks` khi tiến độ nhảy từng chương ⇒ tối đa ~10 lần/giây, giá trị cuối luôn phát.
    internal static let progressPublishInterval: CFAbsoluteTime = 0.1

    @Published public var tasks: [DownloadTask] = []
    public var cancelledTaskIds: Set<UUID> = []
    internal var container: ModelContainer?
    /// Context dùng lại cho mọi CRUD của task. Tạo `ModelContext` mới ở từng lần cập nhật tiến độ là một trong
    /// ba nguồn chậm chính của vòng lặp tải/xuất (hai nguồn còn lại: fetch toàn bảng và `save()` mỗi chương).
    internal var taskContext: ModelContext?
    internal var lastTaskSaveAt: CFAbsoluteTime = 0
    internal var lastProgressPublishAt: [UUID: CFAbsoluteTime] = [:]

    private init() {}

    public func enqueueTask(
        book: Book,
        taskType: TaskType,
        startFromCurrent: Bool,
        limit: ChapterLimitOption,
        translate: Bool,
        onlyExportCached: Bool = false,
        container: ModelContainer
    ) {
        let taskId = UUID()
        let bookId = book.bookId
        let title = book.title
        let cover = book.coverUrl
        let extPkgId = book.extensionPackageId
        let detailUrl = book.detailUrl

        let newTask = DownloadTask(
            id: taskId,
            bookId: bookId,
            bookTitle: title,
            bookCoverUrl: cover,
            taskType: taskType,
            status: .pending,
            progressCount: 0,
            totalCount: 0,
            extensionPackageId: extPkgId,
            detailUrl: detailUrl,
            startFromCurrent: startFromCurrent,
            limit: limit,
            translate: translate,
            onlyExportCached: onlyExportCached
        )

        self.container = container

        let dbModel = DownloadTaskModel(
            id: taskId,
            bookId: bookId,
            bookTitle: title,
            bookCoverUrl: cover,
            taskTypeRaw: taskType.rawValue,
            statusRaw: TaskStatus.pending.rawValue,
            progressCount: 0,
            totalCount: 0,
            extensionPackageId: extPkgId,
            detailUrl: detailUrl,
            startFromCurrent: startFromCurrent,
            limitRaw: limit.rawValue,
            translate: translate,
            onlyExportCached: onlyExportCached
        )

        if let context = taskStoreContext() {
            context.insert(dbModel)
            try? context.save()
            lastTaskSaveAt = CFAbsoluteTimeGetCurrent()
        }

        self.tasks.append(newTask)
        self.runNextTasksIfNeeded(container: container)
    }

    private var activeWorkers: [UUID: BookDownloadWorker] = [:]
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    public var maxConcurrentTasks: Int = 2

    public func cancelTask(taskId: UUID) {
        cancelledTaskIds.insert(taskId)
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = .cancelled
            tasks[index].isCancelled = true

            updateTaskInDB(taskId: taskId) { model in
                model.statusRaw = TaskStatus.cancelled.rawValue
                model.isCancelled = true
            }
        }

        if let handle = activeTasks.removeValue(forKey: taskId) {
            handle.cancel()
        }
        if let worker = activeWorkers.removeValue(forKey: taskId) {
            Task {
                await worker.cancel()
            }
        }

        if let container = self.container {
            runNextTasksIfNeeded(container: container)
        }
    }

    public func cancelTasksForBook(bookId: String) {
        let tasksToCancel = tasks.filter { $0.bookId == bookId && ($0.status == .running || $0.status == .pending) }
        for t in tasksToCancel {
            cancelTask(taskId: t.id)
        }
    }

    internal func runNextTasksIfNeeded(container: ModelContainer) {
        let runningCount = tasks.filter { $0.status == .running }.count
        let availableSlots = max(0, maxConcurrentTasks - runningCount)
        guard availableSlots > 0 else { return }

        let pendingIndices = tasks.enumerated()
            .filter { $0.element.status == .pending }
            .prefix(availableSlots)
            .map { $0.offset }

        for index in pendingIndices {
            tasks[index].status = .running
            let taskToRun = tasks[index]
            let taskId = taskToRun.id

            let taskHandle = Task.detached(priority: .background) {
                await self.executeTask(taskToRun, container: container)
            }
            self.activeTasks[taskId] = taskHandle
        }
    }

    private func executeTask(_ task: DownloadTask, container: ModelContainer) async {
        let bgContext = ModelContext(container)
        let taskId = task.id

        // 2. Fetch Extension by filtering in memory
        let allExts = (try? bgContext.fetch(FetchDescriptor<Extension>())) ?? []
        let bgExt = allExts.first(where: { $0.packageId == task.extensionPackageId })

        let worker: BookDownloadWorker?
        if let bgExt = bgExt {
            worker = BookDownloadWorker(
                localPath: bgExt.localPath,
                downloadUrl: bgExt.downloadUrl,
                configJson: bgExt.configJson
            )
        } else {
            worker = nil
        }
        await MainActor.run {
            if let worker = worker {
                self.activeWorkers[taskId] = worker
            }
        }

        defer {
            Task {
                await worker?.cleanup()
                await MainActor.run {
                    self.activeWorkers.removeValue(forKey: taskId)
                    self.activeTasks.removeValue(forKey: taskId)
                    self.runNextTasksIfNeeded(container: container)
                }
            }
        }

        // Ghi dần bản xuất TXT ra đĩa thay cho bộ đệm chuỗi cũ (giữ cả file trong RAM). Khai ngoài `do`
        // để mọi nhánh lỗi/huỷ đều dọn được file `.part` dở dang.
        var exportWriter: TxtExportFileWriter?

        do {
            // 1. Fetch Book by filtering in memory to avoid SwiftData #Predicate compiler bugs
            let allBooks = (try? bgContext.fetch(FetchDescriptor<Book>())) ?? []
            guard let bgBook = allBooks.first(where: { $0.bookId == task.bookId }) else {
                throw NSError(domain: "DownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy truyện trong cơ sở dữ liệu."])
            }

            // Chỉ đẩy truyện lên kệ khi nó chưa nằm ở đâu (không kệ, không lịch sử) — tôn trọng lựa chọn hiển thị của người dùng
            if !bgBook.isOnShelf && !bgBook.isHistory {
                bgBook.isOnShelf = true
                try? bgContext.save()
            }

            // 3. Prepare chapters to process via ChapterStore or SwiftData
            let sortedChapters: [StoredChapterSnapshot]
            if let storeChaps = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bgBook.bookId), !storeChaps.isEmpty {
                sortedChapters = storeChaps
            } else {
                sortedChapters = bgBook.chapters.sorted(by: { $0.index < $1.index }).map { ch in
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
            }

            let startIdx = task.startFromCurrent ? bgBook.currentChapterIndex : 0

            guard startIdx < sortedChapters.count else {
                throw NSError(domain: "DownloadManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Chỉ mục chương bắt đầu vượt quá số lượng chương hiện có."])
            }

            let limitVal = task.limit.limitValue
            let endIdx = limitVal == nil ? sortedChapters.count : min(startIdx + limitVal!, sortedChapters.count)
            let chapsToProcess = Array(sortedChapters[startIdx..<endIdx])

            let total = chapsToProcess.count
            await self.updateProgress(taskId: taskId, progress: 0, total: total)

            var cachedCount = 0
            var skippedUncachedCount = 0
            var uncachedAttemptCount = 0
            var savedCount = 0
            var failedCount = 0
            var processedCount = 0
            if task.taskType == .exportTxt {
                exportWriter = try TxtExportFileWriter(bookTitle: bgBook.title)
            }

            for chapter in chapsToProcess {
                let targetChapterTitle = chapter.title
                let targetChapterUrl = chapter.url
                let isChapterCached = chapter.isCached

                // Không hop MainActor chỉ để hỏi cờ huỷ nữa: `activeTasks[taskId]` được gán ngay sau
                // `Task.detached`, và mọi đường huỷ (`cancelTask`, `cancelTasksForBook`, `deleteTask`) đều gọi
                // `handle.cancel()` ⇒ `Task.isCancelled` đã phủ hết. Đọc `cancelledTaskIds` từ đây còn là một
                // truy cập `Set` không đồng bộ hoá.
                if Task.isCancelled {
                    exportWriter?.discard()
                    await self.markCancelled(taskId: taskId)
                    return
                }

                // Đọc nội dung cache từ file .bin nếu đã được lưu offline
                var cachedContent: String? = nil
                if isChapterCached && chapter.length > 0 {
                    cachedContent = try? await BookBinManager.shared.readChapterContent(bookId: bgBook.bookId, offset: chapter.offset, length: chapter.length)
                }

                var originalContent = ""

                if isChapterCached, let existingContent = cachedContent, !existingContent.isEmpty {
                    cachedCount += 1
                    originalContent = existingContent
                } else if task.taskType == .exportTxt && task.onlyExportCached {
                    skippedUncachedCount += 1
                    processedCount += 1
                    await self.updateProgress(taskId: taskId, progress: processedCount, total: total)
                    continue
                } else {
                    uncachedAttemptCount += 1
                    do {
                        guard let worker = worker else {
                            failedCount += 1
                            processedCount += 1
                            await self.updateProgress(taskId: taskId, progress: processedCount, total: total)
                            continue
                        }

                        // Download from extension via single sequential worker
                        let content = try await worker.fetchChapterContent(
                            url: targetChapterUrl,
                            host: chapter.host
                        )
                        let cleaned = content.cleanHTML()

                        if cleaned.isEmpty {
                            failedCount += 1
                        } else if let (offset, length) = try? await BookBinManager.shared.writeChapterContent(bookId: bgBook.bookId, content: cleaned) {
                            let meta = ChapterMetadataSnapshot(title: chapter.title, url: targetChapterUrl, index: chapter.index, host: chapter.host, titleTrans: chapter.titleTrans)
                            do {
                                try await ChapterStore.shared.upsertCachedChapter(
                                    bookId: bgBook.bookId,
                                    metadata: meta,
                                    isCached: true,
                                    offset: offset,
                                    length: length
                                )

                                savedCount += 1
                                originalContent = cleaned
                            } catch {
                                failedCount += 1
                            }
                        } else {
                            failedCount += 1
                        }
                    } catch is CancellationError {
                        exportWriter?.discard()
                        await self.markCancelled(taskId: taskId)
                        return
                    } catch {
                        failedCount += 1
                    }
                }

                if task.taskType == .exportTxt && !originalContent.isEmpty {
                    // Format for TXT
                    var titleToExport = targetChapterTitle
                    var contentToExport = originalContent

                    if task.translate {
                        titleToExport = TranslateUtils.translateChapterTitle(titleToExport, bookId: bgBook.bookId)
                        contentToExport = TranslateUtils.translateContent(contentToExport, bookId: bgBook.bookId)
                    }

                    try exportWriter?.append(formatChapter(title: titleToExport, content: contentToExport))
                }

                processedCount += 1
                await self.updateProgress(taskId: taskId, progress: processedCount, total: total)
            }

            // 4. Save and finish outcome
            AppLogger.shared.log("📊 [DownloadManager] Tác vụ \(taskId) hoàn tất xử lý: cachedCount=\(cachedCount), savedCount=\(savedCount), skippedUncachedCount=\(skippedUncachedCount), uncachedAttemptCount=\(uncachedAttemptCount), failedCount=\(failedCount)")
            let outcome = DownloadTaskOutcomeCalculator.calculateOutcome(
                taskType: task.taskType,
                uncachedAttemptCount: uncachedAttemptCount,
                savedCount: savedCount,
                failedCount: failedCount,
                isExportTxtEmpty: exportWriter?.hasNoContent ?? true
            )

            switch outcome {
            case .completed:
                if let exportWriter {
                    let fileURL = try exportWriter.finish()
                    let savedPath = fileURL.path
                    await MainActor.run {
                        self.markCompleted(taskId: taskId, exportFilePath: savedPath)
                        self.presentShareSheet(for: fileURL)
                    }
                } else {
                    await self.markCompleted(taskId: taskId)
                }
            case .failed(let message):
                exportWriter?.discard()
                await self.markFailed(taskId: taskId, error: message)
            }

        } catch is CancellationError {
            exportWriter?.discard()
            await self.markCancelled(taskId: taskId)
        } catch {
            exportWriter?.discard()
            await self.markFailed(taskId: taskId, error: error.localizedDescription)
        }
    }

    private func formatChapter(title: String, content: String) -> String {
        let paragraphs = content.components(separatedBy: .newlines)
        let formattedParagraphs = paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "    " + $0 }
            .joined(separator: "\n\n")
        return "\(title)\n\n\(formattedParagraphs)"
    }

    @MainActor
    public func shareExportedFile(taskId: UUID) {
        guard let task = tasks.first(where: { $0.id == taskId }),
              let path = task.exportFilePath,
              FileManager.default.fileExists(atPath: path) else {
            DownloadPresentationEventCenter.shared.send(.showToast(message: "Tệp xuất không tồn tại hoặc đã bị xóa.", type: .error))
            return
        }
        let fileURL = URL(fileURLWithPath: path)
        presentShareSheet(for: fileURL)
    }

    @MainActor
    public func presentShareSheet(for fileURL: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
              let rootVC = window.rootViewController else {
            AppLogger.shared.log("⚠️ [DownloadManager] Không tìm thấy rootViewController để mở share sheet.")
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        if topVC.isBeingPresented || topVC.isBeingDismissed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.presentShareSheet(for: fileURL)
            }
            return
        }

        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)

        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = topVC.view
            popoverController.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }

        topVC.present(activityVC, animated: true, completion: nil)
    }
}
