import Foundation
import SwiftData

/// Phần CRUD/DB và phát tiến độ của `DownloadManager`.
///
/// Tách khỏi `DownloadManager.swift` (đang vượt baseline dòng) và đồng thời bỏ ba việc dư từng chạy **mỗi chương**:
/// tạo `ModelContext` mới, `fetch(FetchDescriptor<DownloadTaskModel>())` toàn bảng, và `save()` (một fsync).
/// Với truyện vài nghìn chương, ba việc đó cộng lại là nguồn chậm chính của cả tải và xuất TXT — kể cả khi xuất
/// từ cache và không có một request mạng nào.
extension DownloadManager {

    // MARK: - Context dùng lại

    /// `ModelContext` dùng chung cho mọi CRUD của task, tạo một lần rồi giữ lại.
    internal func taskStoreContext() -> ModelContext? {
        if let taskContext { return taskContext }
        guard let container else { return nil }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        taskContext = context
        return context
    }

    /// Lấy đúng một hàng theo `id` thay vì nạp cả bảng rồi `first(where:)`.
    /// `id` là `UUID` nên `#Predicate` an toàn ở đây (bug bộ dịch predicate của SQLite iOS 17 chỉ với chuỗi).
    internal func fetchTaskModel(taskId: UUID, in context: ModelContext) -> DownloadTaskModel? {
        var descriptor = FetchDescriptor<DownloadTaskModel>(predicate: #Predicate<DownloadTaskModel> { $0.id == taskId })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Cập nhật một task trong DB.
    ///
    /// - Parameter coalesce: `true` cho các bước tiến độ trung gian — thay đổi vẫn được áp vào model ngay, nhưng
    ///   `save()` bị gộp lại: chỉ ghi khi đã cách lần ghi trước ≥ `taskSaveCoalesceInterval`. Mọi trạng thái cuối
    ///   (`markCompleted` / `markFailed` / `markCancelled` / huỷ / retry) truyền `false` để ghi chắc chắn.
    internal func updateTaskInDB(taskId: UUID, coalesce: Bool = false, updateBlock: (DownloadTaskModel) -> Void) {
        guard let context = taskStoreContext(),
              let model = fetchTaskModel(taskId: taskId, in: context) else { return }
        updateBlock(model)

        let now = CFAbsoluteTimeGetCurrent()
        if coalesce && now - lastTaskSaveAt < Self.taskSaveCoalesceInterval { return }
        try? context.save()
        lastTaskSaveAt = now
    }

    // MARK: - Vòng đời task

    public func initialize(container: ModelContainer) {
        self.container = container

        guard let context = taskStoreContext() else { return }
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
            lastTaskSaveAt = CFAbsoluteTimeGetCurrent()
            self.tasks = loadedTasks
        } catch {
            AppLogger.shared.log("Error loading download tasks from DB: \(error.localizedDescription)")
        }
    }

    public func deleteTask(taskId: UUID) {
        cancelTask(taskId: taskId)

        if let context = taskStoreContext(), let model = fetchTaskModel(taskId: taskId, in: context) {
            context.delete(model)
            try? context.save()
            lastTaskSaveAt = CFAbsoluteTimeGetCurrent()
        }
        lastProgressPublishAt.removeValue(forKey: taskId)

        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks.remove(at: idx)
        }
    }

    public func retryTask(taskId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let task = tasks[idx]
        guard task.status == .failed || task.status == .cancelled else { return }

        cancelledTaskIds.remove(taskId)
        lastProgressPublishAt.removeValue(forKey: taskId)

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

    public func clearFinishedTasks() {
        let taskIdsToRemove = tasks.filter { task in
            task.status == .completed || task.status == .failed || task.status == .cancelled
        }.map { $0.id }

        tasks.removeAll { task in
            taskIdsToRemove.contains(task.id)
        }

        if let context = taskStoreContext() {
            for taskId in taskIdsToRemove {
                if let model = fetchTaskModel(taskId: taskId, in: context) {
                    context.delete(model)
                }
                lastProgressPublishAt.removeValue(forKey: taskId)
            }
            try? context.save()
            lastTaskSaveAt = CFAbsoluteTimeGetCurrent()
        }
    }

    public func isTaskCancelled(taskId: UUID) -> Bool {
        if cancelledTaskIds.contains(taskId) {
            return true
        }
        return tasks.first(where: { $0.id == taskId })?.isCancelled ?? false
    }

    // MARK: - Tiến độ & trạng thái cuối

    /// Cập nhật tiến độ của một task.
    ///
    /// Mảng `@Published tasks` chỉ được sửa tối đa ~10 lần/giây (`progressPublishInterval`) — giá trị cuối,
    /// bước đầu tiên và mọi thay đổi trạng thái/tổng số luôn được phát — nên progress bar vẫn mượt mà SwiftUI
    /// không phải render lại một lần cho mỗi chương. Giá trị mới vẫn được áp vào model DB ở **mọi** lần gọi,
    /// chỉ riêng `save()` là được gộp.
    @MainActor
    internal func updateProgress(taskId: UUID, progress: Int, total: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }

        let isFinalStep = total > 0 && progress >= total
        let isStateChange = tasks[index].status != .running || tasks[index].totalCount != total
        let now = CFAbsoluteTimeGetCurrent()
        let shouldPublish = isFinalStep || isStateChange || progress == 0
            || now - (lastProgressPublishAt[taskId] ?? 0) >= Self.progressPublishInterval

        if shouldPublish {
            tasks[index].progressCount = progress
            tasks[index].totalCount = total
            tasks[index].status = .running
            lastProgressPublishAt[taskId] = now
        }

        updateTaskInDB(taskId: taskId, coalesce: !isFinalStep) { model in
            model.progressCount = progress
            model.totalCount = total
            model.statusRaw = TaskStatus.running.rawValue
        }
    }

    @MainActor
    internal func markCompleted(taskId: UUID, exportFilePath: String? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].status = .completed
        if let path = exportFilePath {
            tasks[index].exportFilePath = path
        }
        lastProgressPublishAt.removeValue(forKey: taskId)

        updateTaskInDB(taskId: taskId) { model in
            model.statusRaw = TaskStatus.completed.rawValue
            if let path = exportFilePath {
                model.exportFilePath = path
            }
        }

        let title = TranslateUtils.translateBookTitleIfNeeded(tasks[index].bookTitle, bookId: tasks[index].bookId)
        let type = tasks[index].taskType.rawValue
        DownloadPresentationEventCenter.shared.send(.showToast(message: "Đã xong: \(type) '\(title)' thành công!", type: .success))
    }

    /// Đổi giai đoạn của một tác vụ xuất. Chỉ là trạng thái hiển thị (không ghi CSDL) nên không cần
    /// coalesce: mỗi tác vụ đi qua tối đa 3 giai đoạn.
    @MainActor
    internal func updateExportStage(taskId: UUID, stage: ExportStage) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].exportStage = stage
    }

    /// Kết thúc một tác vụ **xuất**: lưu đường dẫn artifact, ghi dòng tổng kết nếu bản xuất thiếu chương,
    /// rồi phát `exportReady` để tầng Views mở share sheet.
    ///
    /// Tách khỏi `markCompleted` vì tác vụ xuất chỉ được coi là xong khi đã có file thật trên đĩa —
    /// `DownloadManager.executeTask` kiểm `artifact.exists` trước khi gọi hàm này.
    @MainActor
    internal func markExportCompleted(taskId: UUID, artifact: ExportArtifact, summary: String?) {
        let path = artifact.fileURL.path
        markCompleted(taskId: taskId, exportFilePath: path)
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].exportStage = .readyToShare
        tasks[index].exportSummary = summary
        if let summary {
            DownloadPresentationEventCenter.shared.send(.showToast(message: summary, type: .info))
        }
        DownloadPresentationEventCenter.shared.send(
            .exportReady(filePath: path, bookTitle: tasks[index].bookTitle)
        )
    }

    @MainActor
    internal func markFailed(taskId: UUID, error: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].status = .failed
        tasks[index].errorMessage = error
        lastProgressPublishAt.removeValue(forKey: taskId)

        updateTaskInDB(taskId: taskId) { model in
            model.statusRaw = TaskStatus.failed.rawValue
            model.errorMessage = error
        }

        let title = TranslateUtils.translateBookTitleIfNeeded(tasks[index].bookTitle, bookId: tasks[index].bookId)
        let type = tasks[index].taskType.rawValue
        DownloadPresentationEventCenter.shared.send(.showToast(message: "Lỗi \(type) '\(title)': \(error)", type: .error))
    }

    @MainActor
    internal func markCancelled(taskId: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].status = .cancelled
        lastProgressPublishAt.removeValue(forKey: taskId)

        updateTaskInDB(taskId: taskId) { model in
            model.statusRaw = TaskStatus.cancelled.rawValue
        }

        let title = TranslateUtils.translateBookTitleIfNeeded(tasks[index].bookTitle, bookId: tasks[index].bookId)
        let type = tasks[index].taskType.rawValue
        DownloadPresentationEventCenter.shared.send(.showToast(message: "Đã hủy tác vụ: \(type) '\(title)'", type: .info))
    }
}
