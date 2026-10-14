import Foundation

/// Luồng quét tên riêng nhiều chương của `AIRuntimeCoordinator` — tách khỏi file gốc (sát trần 400 dòng) theo mẫu
/// `X+Feature.swift` (1.3.524). Vì vậy `batchRunId`/`activeBatchTask` là `internal` và `isRunning`/`activeTaskTitle`
/// có setter `internal` thay vì `private`. Nút "Thử lại k lượt lỗi" nằm ở `+NameScanRetry.swift` (1.3.527) và dùng
/// chung các helper `internal` ở cuối file này.
extension AIRuntimeCoordinator {
    /// Bắt đầu quét tên riêng các chương đã tải (batch), có thể giới hạn phạm vi và số chương.
    /// `session` khác nil ⇒ Gemini Web (bật lưu lịch sử) quét nối tiếp đúng cuộc chat Gemini của phiên này.
    /// `onProgress` nhận danh sách tên `nil` khi chỉ đổi tiến độ (báo "đang gửi lượt N"), tên giữ nguyên.
    /// Lượt vẫn lỗi sau vòng tự thử lại được giữ trong RAM (`nameScanRetryContext`) cho nút "Thử lại k lượt lỗi".
    public func startBatchExtraction(
        bookId: String,
        config: AIConfiguration,
        promptOverride: String? = nil,
        fromChapterIndex: Int? = nil,
        limit: Int? = nil,
        session: AIChatSession? = nil,
        assistantMsgId: UUID? = nil,
        onProgress: @escaping (AINameScanProgress, [AIExtractedName]?) -> Void,
        onComplete: @escaping ([AIExtractedName]) -> Void
    ) {
        cancelActiveTask()
        // Lần quét mới thay lần cũ ⇒ bỏ các lượt lỗi còn giữ của lần trước (người dùng đã chọn: không giữ qua lần quét).
        setNameScanRetry(nil)
        isRunning = true
        let initialProgress = AINameScanProgress()
        batchProgress = initialProgress
        activeTaskTitle = Self.batchTaskTitle(for: initialProgress)
        let runId = UUID()
        batchRunId = runId
        batchExtractedNames.removeAll()
        if let s = session {
            self.activeSession = s
            self.activeSessionId = s.id
        }
        let sessionId = session?.id

        activeBatchTask = Task { [weak self] in
            do {
                let outcome = try await AINameExtractionBatchProcessor.shared.extractNamesFromDownloadedChapters(
                    bookId: bookId,
                    config: config,
                    promptOverride: promptOverride,
                    fromChapterIndex: fromChapterIndex,
                    limit: limit,
                    sessionId: sessionId
                ) { progress, partial in
                    // Chỉ gắn cờ NE/VP khi danh sách tên đổi — báo "đang gửi lượt N" không kèm tên.
                    let decorated = partial.map { AIBookDataInspector.shared.decorateExtractedNames(names: $0, bookId: bookId) }
                    Task { @MainActor [weak self] in
                        // `Task.isCancelled` ở đây là của Task MỚI này (không bao giờ bị huỷ) ⇒ phải so mã lần chạy.
                        guard let self = self, self.batchRunId == runId else { return }
                        self.applyBatchProgress(progress, names: decorated, assistantMsgId: assistantMsgId)
                        onProgress(progress, decorated)
                    }
                }
                guard !Task.isCancelled else { return }
                // Task này kế thừa MainActor; gắn cờ NE/VP đọc Names.txt/VietPhrase.txt và tra từ điển cho cả
                // danh sách — chạy ngoài main thread như các lượt giữa chừng (ở callback tiến độ).
                let results = outcome.names
                let finalResults = await Task.detached(priority: .userInitiated) {
                    AIBookDataInspector.shared.decorateExtractedNames(names: results, bookId: bookId)
                }.value
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    // Lần chạy đã bị thay (dừng / lệnh mới) thì `cancelActiveTask` đã dọn trạng thái — không ghi đè.
                    guard let self = self, self.batchRunId == runId else { return }
                    self.endBatchRun()
                    self.batchExtractedNames = finalResults
                    self.writeNames(finalResults, toMessage: assistantMsgId)
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    if let mid = assistantMsgId, !outcome.failedBatches.isEmpty {
                        self.setNameScanRetry(NameScanRetryContext(
                            bookId: bookId,
                            config: config,
                            promptOverride: promptOverride,
                            sessionId: sessionId,
                            assistantMsgId: mid,
                            names: finalResults,
                            failedBatches: outcome.failedBatches
                        ))
                    }
                    onComplete(finalResults)
                    self.showBatchCompletionToast(nameCount: finalResults.count, progress: outcome.progress)
                }
            } catch {
                await MainActor.run {
                    guard let self = self, self.batchRunId == runId else { return }
                    self.endBatchRun()
                    if let mid = assistantMsgId, let idx = self.activeSession?.messages.firstIndex(where: { $0.id == mid }) {
                        self.activeSession?.messages[idx].content = "Lỗi quét tên riêng: \(error.localizedDescription)"
                        self.activeSession?.messages[idx].isStreaming = false
                    }
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    if !self.isFullScreenPresented {
                        ToastManager.shared.show(message: "Quét tên riêng bị gián đoạn.", type: .error)
                    }
                }
            }
        }
    }

    /// Ghi tiến độ của lần quét hiện hành lên dải batch, tiêu đề widget thu nhỏ và (khi tên đổi) tin trợ lý đang chạy.
    func applyBatchProgress(_ progress: AINameScanProgress, names: [AIExtractedName]?, assistantMsgId: UUID?) {
        batchProgress = progress
        activeTaskTitle = Self.batchTaskTitle(for: progress)
        guard let names else { return }
        batchExtractedNames = names
        let text = names.map { "\($0.original)=\($0.suggestedMeaning)" }.joined(separator: "\n")
        if let mid = assistantMsgId, let idx = activeSession?.messages.firstIndex(where: { $0.id == mid }) {
            activeSession?.messages[idx].content = text
            activeSession?.messages[idx].isStreaming = true
        }
    }

    /// Kết thúc lần chạy quét/thử lại hiện hành (xong hoặc lỗi).
    ///
    /// Bắt buộc `batchProgress = nil`: `@Published` phát lại giá trị hiện tại cho subscriber mới, nên để
    /// `batchProgress` khác nil sau khi xong thì mỗi lần màn AI dựng lại, thanh tiến trình cũ sống dậy và không còn
    /// emission nào tắt nó.
    func endBatchRun() {
        isRunning = false
        activeBatchTask = nil
        batchRunId = nil
        batchProgress = nil
    }

    /// Ghi danh sách `Tên=Nghĩa` cuối cùng vào tin kết quả và đánh dấu tin đã xong.
    func writeNames(_ names: [AIExtractedName], toMessage messageId: UUID?) {
        guard let mid = messageId, let idx = activeSession?.messages.firstIndex(where: { $0.id == mid }) else { return }
        let text = names.map { "\($0.original)=\($0.suggestedMeaning)" }.joined(separator: "\n")
        activeSession?.messages[idx].content = text.isEmpty ? "Không có name" : text
        activeSession?.messages[idx].isStreaming = false
    }

    /// Có lượt lỗi ⇒ toast lỗi **kể cả khi màn AI đang mở**: tin kết quả chỉ giữ danh sách `Tên=Nghĩa` sạch để sao
    /// chép/duyệt, nên đây là chỗ duy nhất người dùng biết có lượt bị bỏ qua (cùng nút "Thử lại k lượt lỗi"). Từ 1.3.527
    /// số lượt lỗi là số lượt **vẫn** lỗi sau vòng tự thử lại. Không lỗi ⇒ toast thành công như cũ, chỉ khi màn AI đóng.
    private func showBatchCompletionToast(nameCount: Int, progress: AINameScanProgress) {
        if progress.failedBatches > 0 {
            let suffix = progress.isRetry ? "lượt vẫn lỗi sau khi thử lại" : "lượt lỗi đã bỏ qua"
            ToastManager.shared.show(
                message: "Đã quét xong \(nameCount) tên riêng · \(progress.failedBatches)/\(progress.totalBatches) \(suffix)",
                type: .error
            )
        } else if !isFullScreenPresented {
            ToastManager.shared.show(message: "Đã quét xong \(nameCount) tên riêng!", type: .success)
        }
    }

    /// Tiêu đề cho widget AI thu nhỏ — cùng nghĩa với dải tiến độ: N là lượt **đang gửi**.
    static func batchTaskTitle(for progress: AINameScanProgress) -> String {
        if progress.isPreparing {
            return progress.isRetry ? "Đang chuẩn bị thử lại..." : "Đang chuẩn bị quét..."
        }
        let verb = progress.isRetry ? "Đang thử lại" : "Đang quét"
        return "\(verb): Batch \(progress.sendingBatch)/\(progress.totalBatches)"
    }
}
