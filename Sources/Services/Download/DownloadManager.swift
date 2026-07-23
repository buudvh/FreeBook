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
}

public final class DownloadManager: ObservableObject {
    public static let shared = DownloadManager()

    @Published public var tasks: [DownloadTask] = []
    private let chapterRepository: any ChapterRepositoryProtocol

    public init(chapterRepository: any ChapterRepositoryProtocol) {
        self.chapterRepository = chapterRepository
    }

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
                    onlyExportCached: model.onlyExportCached
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

        tasks[idx].status = .pending
        tasks[idx].progressCount = 0
        tasks[idx].errorMessage = nil

        if let container = self.container {
            updateTaskInDB(taskId: taskId) { model in
                model.statusRaw = "pending"
                model.progressCount = 0
                model.errorMessage = nil
            }
            runNextTaskIfNeeded(container: container)
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
        self.runNextTaskIfNeeded(container: container)
    }

    public func cancelTask(taskId: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = .cancelled
            tasks[index].isCancelled = true

            updateTaskInDB(taskId: taskId) { model in
                model.statusRaw = TaskStatus.cancelled.rawValue
                model.isCancelled = true
            }
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
    private func markCompleted(taskId: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = .completed

            updateTaskInDB(taskId: taskId) { model in
                model.statusRaw = TaskStatus.completed.rawValue
            }

            let title = tasks[index].bookTitle
            let type = tasks[index].taskType.rawValue
            ToastManager.shared.show(message: "Đã xong: \(type) '\(title)' thành công!", type: .success)
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
            ToastManager.shared.show(message: "Lỗi \(type) '\(title)': \(error)", type: .error)
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
            ToastManager.shared.show(message: "Đã hủy tác vụ: \(type) '\(title)'")
        }
    }

    private func runNextTaskIfNeeded(container: ModelContainer) {
        // Find the first pending task
        guard let nextTaskIndex = tasks.firstIndex(where: { $0.status == .pending }) else {
            return
        }

        // If there's already a task running, wait
        guard !tasks.contains(where: { $0.status == .running }) else {
            return
        }

        tasks[nextTaskIndex].status = .running
        let taskToRun = tasks[nextTaskIndex]

        Task.detached(priority: .background) {
            await self.executeTask(taskToRun, container: container)
        }
    }

    private func executeTask(_ task: DownloadTask, container: ModelContainer) async {
        let bgContext = ModelContext(container)
        let taskId = task.id

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

            // 2. Fetch Extension by filtering in memory
            let allExts = (try? bgContext.fetch(FetchDescriptor<Extension>())) ?? []
            guard let bgExt = allExts.first(where: { $0.packageId == task.extensionPackageId }) else {
                throw NSError(domain: "DownloadManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tiện ích bóc tách cho truyện này."])
            }

            // 3. Prepare chapters to process
            let allChapters = (try? await self.chapterRepository.loadPageKeyset(bookId: bgBook.bookId, startIdx: 0, limit: 100000)) ?? []
            let sortedChapters = allChapters.sorted(by: { $0.index < $1.index })
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

            var processedCount = 0
            var txtAccumulator = ""

            for chapter in chapsToProcess {
                let targetChapterId = chapter.id
                let targetChapterTitle = chapter.title
                let targetChapterUrl = chapter.url
                let isChapterCached = chapter.isCached

                // Đọc nội dung cache từ file .bin nếu đã được lưu offline
                var cachedContent: String? = nil
                if isChapterCached && chapter.length > 0 {
                    cachedContent = try? await BookBinManager.shared.readChapterContent(bookId: bgBook.bookId, offset: chapter.offset, length: chapter.length)
                }

                // Check if cancelled
                let isCancelled = await MainActor.run {
                    self.isTaskCancelled(taskId: taskId)
                }
                if isCancelled {
                    await MainActor.run {
                        self.markCancelled(taskId: taskId)
                        self.runNextTaskIfNeeded(container: container)
                    }
                    return
                }

                var originalContent = ""

                if isChapterCached, let existingContent = cachedContent, !existingContent.isEmpty {
                    originalContent = existingContent
                } else {
                    if task.taskType == .exportTxt && task.onlyExportCached {
                        // Skip this chapter as it is not cached
                        processedCount += 1
                        continue
                    }

                    // Download from extension
                    let content = try await ExtensionManager.shared.chap(
                        localPath: bgExt.localPath,
                        downloadUrl: bgExt.downloadUrl,
                        url: targetChapterUrl,
                        host: chapter.host,
                        configJson: bgExt.configJson
                    )
                    let cleaned = content.cleanHTML()

                    if let (offset, length) = try? await BookBinManager.shared.writeChapterContent(bookId: bgBook.bookId, content: cleaned) {
                        try? await self.chapterRepository.updateCacheState(bookId: bgBook.bookId, index: chapter.index, offset: offset, length: length, isCached: true)
                    }
                    originalContent = cleaned
                }

                if task.taskType == .exportTxt {
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

            // 4. Save and finish
            if task.taskType == .exportTxt {
                let tempDir = FileManager.default.temporaryDirectory
                let sanitizedTitle = bgBook.title.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
                let fileName = "\(sanitizedTitle).txt"
                let fileURL = tempDir.appendingPathComponent(fileName)
                try txtAccumulator.write(to: fileURL, atomically: true, encoding: .utf8)

                await MainActor.run {
                    self.markCompleted(taskId: taskId)
                    self.presentShareSheet(for: fileURL)
                    self.runNextTaskIfNeeded(container: container)
                }
            } else {
                await MainActor.run {
                    self.markCompleted(taskId: taskId)
                    self.runNextTaskIfNeeded(container: container)
                }
            }

        } catch {
            await MainActor.run {
                self.markFailed(taskId: taskId, error: error.localizedDescription)
                self.runNextTaskIfNeeded(container: container)
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
    private func presentShareSheet(for fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
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
