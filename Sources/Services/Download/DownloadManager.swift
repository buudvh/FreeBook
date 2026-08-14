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

    @Published public var tasks: [DownloadTask] = []
    public var cancelledTaskIds: Set<UUID> = []
    private var container: ModelContainer?

    private init() {}

    public func initialize(container: ModelContainer) {
        self.container = container

        let context = ModelContext(container)
        do {
            let descriptor = FetchDescriptor<DownloadTaskModel>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
            let models = try context.fetch(descriptor)

            var loadedTasks: [DownloadTask] = []
            for model in models {
                var task = DownloadTask(
                    id: model.id,
                    bookId: model.bookId,
                    bookTitle: model.bookTitle,
                    bookCoverUrl: model.bookCoverUrl,
                    taskType: TaskType(rawValue: model.taskTypeRaw) ?? .download,
                    status: TaskStatus(rawValue: model.statusRaw) ?? .pending,
                    progressCount: model.progressCount,
                    totalCount: model.totalCount,
                    errorMessage: model.errorMessage,
                    isCancelled: model.isCancelled,
                    extensionPackageId: model.extensionPackageId,
                    detailUrl: model.detailUrl,
                    startFromCurrent: model.startFromCurrent,
                    limit: ChapterLimitOption(rawValue: model.limitRaw) ?? .all,
                    translate: model.translate,
                    onlyExportCached: model.onlyExportCached,
                    exportFilePath: model.exportFilePath
                )

                if task.status == .running || task.status == .pending {
                    task.status = .failed
                    task.errorMessage = "Tác vụ bị dừng đột ngột (ứng dụng khởi động lại)"

                    model.statusRaw = TaskStatus.failed.rawValue
                    model.errorMessage = "Tác vụ bị dừng đột ngột (ứng dụng khởi động lại)"
                }

                loadedTasks.append(task)
            }
            try? context.save()
            self.tasks = loadedTasks
        } catch {
            AppLogger.shared.log("Error loading download tasks from DB: \(error.localizedDescription)")
        }
    }

    public func deleteTask(taskId: UUID) {
        cancelTask(taskId: taskId)

        guard let container = container else { return }
        let context = ModelContext(container)
        let allModels = (try? context.fetch(FetchDescriptor<DownloadTaskModel>())) ?? []
        if let model = allModels.first(where: { $0.id == taskId }) {
            context.delete(model)
            try? context.save()
        }

        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks.remove(at: idx)
        }
    }

    public func retryTask(taskId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let task = tasks[idx]
        guard task.status == .failed || task.status == .cancelled else { return }

        cancelledTaskIds.remove(taskId)

        tasks[idx].status = .pending
        tasks[idx].isCancelled = false
        tasks[idx].progressCount = 0
        tasks[idx].errorMessage = nil

        if let container = self.container {
            updateTaskInDB(taskId: taskId) { model in
                model.statusRaw = TaskStatus.pending.rawValue
                model.isCancelled = false
                model.progressCount = 0
                model.errorMessage = nil
            }
            runNextTasksIfNeeded(container: container)
        }
    }

    private func updateTaskInDB(taskId: UUID, updateBlock: (DownloadTaskModel) -> Void) {
        guard let container = container else { return }
        let context = ModelContext(container)
        let allModels = (try? context.fetch(FetchDescriptor<DownloadTaskModel>())) ?? []
        if let model = allModels.first(where: { $0.id == taskId }) {
            updateBlock(model)
            try? context.save()
        }
    }

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

        let context = ModelContext(container)
        context.insert(dbModel)
        try? context.save()

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

    public func clearFinishedTasks() {
        let taskIdsToRemove = tasks.filter { task in
            task.status == .completed || task.status == .failed || task.status == .cancelled
        }.map { $0.id }

        tasks.removeAll { task in
            taskIdsToRemove.contains(task.id)
        }

        if let container = container {
            let context = ModelContext(container)
            let allModels = (try? context.fetch(FetchDescriptor<DownloadTaskModel>())) ?? []
            for model in allModels {
                if taskIdsToRemove.contains(model.id) {
                    context.delete(model)
                }
            }
            try? context.save()
        }
    }

    public func isTaskCancelled(taskId: UUID) -> Bool {
        if cancelledTaskIds.contains(taskId) {
            return true
        }
        return tasks.first(where: { $0.id == taskId })?.isCancelled ?? false
    }

    @MainActor
    private func updateProgress(taskId: UUID, progress: Int, total: Int) {
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].progressCount = progress
            tasks[index].totalCount = total
            tasks[index].status = .running

            updateTaskInDB(taskId: taskId) { model in
                model.progressCount = progress
                model.totalCount = total
                model.statusRaw = TaskStatus.running.rawValue
            }
        }
    }

    @MainActor
    private func markCompleted(taskId: UUID, exportFilePath: String? = nil) {
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = .completed
            if let path = exportFilePath {
                tasks[index].exportFilePath = path
            }

            updateTaskInDB(taskId: taskId) { model in
                model.statusRaw = TaskStatus.completed.rawValue
                if let path = exportFilePath {
                    model.exportFilePath = path
                }
            }

            let title = tasks[index].bookTitle
            let type = tasks[index].taskType.rawValue
            DownloadPresentationEventCenter.shared.send(.showToast(message: "Đã xong: \(type) '\(title)' thành công!", type: .success))
        }
    }

    @MainActor
    private func markFailed(taskId: UUID, error: String) {
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = .failed
            tasks[index].errorMessage = error

            updateTaskInDB(taskId: taskId) { model in
                model.statusRaw = TaskStatus.failed.rawValue
                model.errorMessage = error
            }

            let title = tasks[index].bookTitle
            let type = tasks[index].taskType.rawValue
            DownloadPresentationEventCenter.shared.send(.showToast(message: "Lỗi \(type) '\(title)': \(error)", type: .error))
        }
    }

    @MainActor
    private func markCancelled(taskId: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = .cancelled

            updateTaskInDB(taskId: taskId) { model in
                model.statusRaw = TaskStatus.cancelled.rawValue
            }

            let title = tasks[index].bookTitle
            let type = tasks[index].taskType.rawValue
            DownloadPresentationEventCenter.shared.send(.showToast(message: "Đã hủy tác vụ: \(type) '\(title)'", type: .info))
        }
    }

    private func runNextTasksIfNeeded(container: ModelContainer) {
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

        do {
            // 1. Fetch Book by filtering in memory to avoid SwiftData #Predicate compiler bugs
            let allBooks = (try? bgContext.fetch(FetchDescriptor<Book>())) ?? []
            guard let bgBook = allBooks.first(where: { $0.bookId == task.bookId }) else {
                throw NSError(domain: "DownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy truyện trong cơ sở dữ liệu."])
            }

            // Đảm bảo truyện được lưu vào kệ sách khi tải xuống hoặc xuất
            if !bgBook.isOnShelf {
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
            await MainActor.run {
                self.updateProgress(taskId: taskId, progress: 0, total: total)
            }

            var cachedCount = 0
            var skippedUncachedCount = 0
            var uncachedAttemptCount = 0
            var savedCount = 0
            var failedCount = 0
            var processedCount = 0
            var txtAccumulator = ""

            for chapter in chapsToProcess {
                let targetChapterTitle = chapter.title
                let targetChapterUrl = chapter.url
                let isChapterCached = chapter.isCached

                // Check if cancelled
                let isCancelled = await MainActor.run {
                    Task.isCancelled || self.isTaskCancelled(taskId: taskId)
                }
                if isCancelled {
                    await MainActor.run {
                        self.markCancelled(taskId: taskId)
                    }
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
                    let currentProgress = processedCount
                    await MainActor.run {
                        self.updateProgress(taskId: taskId, progress: currentProgress, total: total)
                    }
                    continue
                } else {
                    uncachedAttemptCount += 1
                    do {
                        guard let worker = worker else {
                            failedCount += 1
                            processedCount += 1
                            let currentProgress = processedCount
                            await MainActor.run {
                                self.updateProgress(taskId: taskId, progress: currentProgress, total: total)
                            }
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
                        await MainActor.run {
                            self.markCancelled(taskId: taskId)
                        }
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

                    let formatted = formatChapter(title: titleToExport, content: contentToExport)
                    if !txtAccumulator.isEmpty {
                        txtAccumulator += "\n\n"
                    }
                    txtAccumulator += formatted
                }

                processedCount += 1
                let currentProgress = processedCount
                await MainActor.run {
                    self.updateProgress(taskId: taskId, progress: currentProgress, total: total)
                }
            }

            // 4. Save and finish outcome
            AppLogger.shared.log("📊 [DownloadManager] Tác vụ \(taskId) hoàn tất xử lý: cachedCount=\(cachedCount), savedCount=\(savedCount), skippedUncachedCount=\(skippedUncachedCount), uncachedAttemptCount=\(uncachedAttemptCount), failedCount=\(failedCount)")
            let isExportTxtEmpty = txtAccumulator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let outcome = DownloadTaskOutcomeCalculator.calculateOutcome(
                taskType: task.taskType,
                uncachedAttemptCount: uncachedAttemptCount,
                savedCount: savedCount,
                failedCount: failedCount,
                isExportTxtEmpty: isExportTxtEmpty
            )

            switch outcome {
            case .completed:
                if task.taskType == .exportTxt {
                    let exportDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Exports", isDirectory: true)
                    try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

                    let sanitizedTitle = bgBook.title.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
                    let fileName = "\(sanitizedTitle).txt"
                    let fileURL = exportDir.appendingPathComponent(fileName)
                    try txtAccumulator.write(to: fileURL, atomically: true, encoding: .utf8)
                    let savedPath = fileURL.path

                    await MainActor.run {
                        self.markCompleted(taskId: taskId, exportFilePath: savedPath)
                        self.presentShareSheet(for: fileURL)
                    }
                } else {
                    await MainActor.run {
                        self.markCompleted(taskId: taskId)
                    }
                }
            case .failed(let message):
                await MainActor.run {
                    self.markFailed(taskId: taskId, error: message)
                }
            }

        } catch is CancellationError {
            await MainActor.run {
                self.markCancelled(taskId: taskId)
            }
        } catch {
            await MainActor.run {
                self.markFailed(taskId: taskId, error: error.localizedDescription)
            }
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
