import Foundation

/// Nút "Thử lại k lượt lỗi" của quét tên riêng nhiều chương (1.3.527).
///
/// Lần quét xong (không bị dừng, không dừng vì lỗi tài khoản/hạn mức) mà còn lượt **vẫn** lỗi sau vòng tự thử lại ⇒
/// coordinator giữ các lượt đó **chỉ trong RAM** (người dùng chọn: mất khi thoát app, xoá khi bắt đầu quét mới) cùng
/// mọi thứ cần để chạy lại: sách, cấu hình (đúng model của lần quét ⇒ vẫn nối tiếp đúng cuộc chat Gemini), prompt,
/// phiên, id tin kết quả và danh sách tên hiện có để gộp. Mỗi lần bấm chạy **một** vòng, không tự thử lại thêm.
extension AIRuntimeCoordinator {
    /// Thông tin tối thiểu cho UI: nút hiện dưới tin `messageId`, nhãn "Thử lại `failedCount` lượt lỗi".
    public struct NameScanRetryInfo: Equatable {
        public let messageId: UUID
        public let failedCount: Int
    }

    /// Đủ để chạy lại các lượt lỗi và ghi đè đúng tin kết quả cũ.
    struct NameScanRetryContext: Sendable {
        let bookId: String
        let config: AIConfiguration
        let promptOverride: String?
        let sessionId: UUID?
        let assistantMsgId: UUID
        var names: [AIExtractedName]
        var failedBatches: [AINameScanFailedBatch]
    }

    /// Nơi duy nhất ghi `nameScanRetryContext` — giữ `nameScanRetry` (phát cho UI) luôn khớp với nó.
    func setNameScanRetry(_ context: NameScanRetryContext?) {
        nameScanRetryContext = context
        nameScanRetry = context.map { NameScanRetryInfo(messageId: $0.assistantMsgId, failedCount: $0.failedBatches.count) }
    }

    /// Chạy lại các lượt còn lỗi rồi ghi đè danh sách gộp vào **đúng** tin kết quả cũ. Vòng đời giống
    /// `startBatchExtraction`: huỷ tác vụ đang chạy, `isRunning`, `batchProgress` (về `nil` ở mọi lối ra), so
    /// `batchRunId` ở mọi cập nhật trễ. Trả `false` (không làm gì) khi không còn lượt nào để thử lại.
    /// Lỗi tài khoản/hạn mức giữa chừng ⇒ giữ nguyên tin kết quả và các lượt lỗi cũ (bấm lại được), chỉ báo toast.
    @discardableResult
    public func retryFailedNameScanBatches(
        session: AIChatSession?,
        onProgress: @escaping (AINameScanProgress, [AIExtractedName]?) -> Void,
        onComplete: @escaping ([AIExtractedName]) -> Void
    ) -> Bool {
        guard let context = nameScanRetryContext, !context.failedBatches.isEmpty else { return false }
        cancelActiveTask()
        isRunning = true
        let initialProgress = AINameScanProgress(sendingBatch: 1, totalBatches: context.failedBatches.count, isRetry: true)
        batchProgress = initialProgress
        activeTaskTitle = Self.batchTaskTitle(for: initialProgress)
        let runId = UUID()
        batchRunId = runId
        batchExtractedNames = context.names
        if let s = session {
            activeSession = s
            activeSessionId = s.id
        }
        let bookId = context.bookId
        let messageId = context.assistantMsgId
        if let idx = activeSession?.messages.firstIndex(where: { $0.id == messageId }) {
            activeSession?.messages[idx].isStreaming = true
        }

        activeBatchTask = Task { [weak self] in
            do {
                let outcome = try await AINameExtractionBatchProcessor.shared.retryFailedBatches(
                    context.failedBatches,
                    existingNames: context.names,
                    config: context.config,
                    promptOverride: context.promptOverride,
                    sessionId: context.sessionId
                ) { progress, partial in
                    // Danh sách báo về đã gộp sẵn với tên cũ ⇒ tin kết quả không mất tên trong lúc thử lại.
                    let decorated = partial.map { AIBookDataInspector.shared.decorateExtractedNames(names: $0, bookId: bookId) }
                    Task { @MainActor [weak self] in
                        guard let self = self, self.batchRunId == runId else { return }
                        self.applyBatchProgress(progress, names: decorated, assistantMsgId: messageId)
                        onProgress(progress, decorated)
                    }
                }
                guard !Task.isCancelled else { return }
                let results = outcome.names
                let finalResults = await Task.detached(priority: .userInitiated) {
                    AIBookDataInspector.shared.decorateExtractedNames(names: results, bookId: bookId)
                }.value
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self = self, self.batchRunId == runId else { return }
                    self.endBatchRun()
                    self.batchExtractedNames = finalResults
                    self.writeNames(finalResults, toMessage: messageId)
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    var remaining = context
                    remaining.names = finalResults
                    remaining.failedBatches = outcome.failedBatches
                    self.setNameScanRetry(outcome.failedBatches.isEmpty ? nil : remaining)
                    onComplete(finalResults)
                    self.showRetryCompletionToast(
                        nameCount: finalResults.count,
                        stillFailed: outcome.failedBatches,
                        retriedCount: context.failedBatches.count
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self = self, self.batchRunId == runId else { return }
                    self.endBatchRun()
                    // Giữ nguyên nội dung tin (danh sách đã gộp tới lúc dừng) và các lượt lỗi cũ: lần bấm sau gộp lại
                    // từ danh sách đã lưu nên không cộng trùng số lần xuất hiện.
                    if let idx = self.activeSession?.messages.firstIndex(where: { $0.id == messageId }) {
                        self.activeSession?.messages[idx].isStreaming = false
                    }
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    ToastManager.shared.show(message: "Thử lại lượt lỗi bị gián đoạn: \(error.localizedDescription)", type: .error)
                }
            }
        }
        return true
    }

    /// Còn lượt lỗi ⇒ toast lỗi kể cả khi màn AI đang mở (nút vẫn còn, nhãn đổi số). Hết lỗi ⇒ toast thành công
    /// như quét thường: chỉ khi màn AI đóng (mở thì nút biến mất và tin đã cập nhật).
    private func showRetryCompletionToast(nameCount: Int, stillFailed: [AINameScanFailedBatch], retriedCount: Int) {
        if let first = stillFailed.first {
            ToastManager.shared.show(
                message: "Thử lại xong \(retriedCount) lượt: \(nameCount) tên riêng · còn \(stillFailed.count)/\(first.totalTurns) lượt lỗi",
                type: .error
            )
        } else if !isFullScreenPresented {
            ToastManager.shared.show(message: "Thử lại xong, đã đủ \(nameCount) tên riêng!", type: .success)
        }
    }
}
