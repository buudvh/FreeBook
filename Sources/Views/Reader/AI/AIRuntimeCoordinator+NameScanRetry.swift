import Foundation

/// Nút "Thử lại k lượt lỗi" của quét tên riêng nhiều chương (1.3.527).
///
/// Lần quét xong (không bị dừng, không dừng vì lỗi tài khoản/hạn mức) mà còn lượt **vẫn** lỗi sau vòng tự thử lại ⇒
/// coordinator giữ các lượt đó **chỉ trong RAM** (người dùng chọn: mất khi thoát app, xoá khi bắt đầu quét mới) cùng
/// mọi thứ cần để chạy lại: sách, cấu hình (đúng model của lần quét ⇒ vẫn nối tiếp đúng cuộc chat Gemini), prompt,
/// phiên, id tin kết quả và danh sách tên hiện có để gộp. Mỗi lần bấm chạy **một** vòng, không tự thử lại thêm.
/// Từ 1.3.558 giữ riêng theo truyện (`nameScanRetryContexts[bookId]`, `runs[bookId].nameScanRetry`).
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
        /// Bộ theo dõi điểm tiếp nối của lần quét gốc (1.3.602): lượt thử lại thành công đẩy điểm tiếp nối đi tiếp theo
        /// luật "dừng trước lượt lỗi".
        let resume: AINameScanResumeTracker?
    }

    /// Nơi duy nhất ghi `nameScanRetryContexts` — giữ `runs[bookId].nameScanRetry` (phát cho UI) luôn khớp với nó.
    func setNameScanRetry(_ context: NameScanRetryContext?, bookId: String) {
        nameScanRetryContexts[bookId] = context
        updateRun(bookId) { state in
            state.nameScanRetry = context.map {
                NameScanRetryInfo(messageId: $0.assistantMsgId, failedCount: $0.failedBatches.count)
            }
        }
    }

    /// Chạy lại các lượt còn lỗi của truyện rồi ghi đè danh sách gộp vào **đúng** tin kết quả cũ. Vòng đời giống
    /// `startBatchExtraction`: chỉ thay tác vụ của chính truyện này, so mã lượt ở mọi cập nhật trễ, `batchProgress`
    /// về `nil` ở mọi lối ra (`endRun`). Trả `false` (không làm gì) khi không còn lượt nào để thử lại.
    /// Lỗi tài khoản/hạn mức giữa chừng ⇒ giữ nguyên tin kết quả và các lượt lỗi cũ (bấm lại được), chỉ báo toast.
    @discardableResult
    public func retryFailedNameScanBatches(
        bookId: String,
        bookTitle: String,
        session: AIChatSession?,
        onProgress: @escaping (AINameScanProgress, [AIExtractedName]?) -> Void,
        onComplete: @escaping ([AIExtractedName]) -> Void
    ) -> Bool {
        guard let context = nameScanRetryContexts[bookId], !context.failedBatches.isEmpty else { return false }
        let initialProgress = AINameScanProgress(sendingBatch: 1, totalBatches: context.failedBatches.count, isRetry: true)
        let runId = beginRun(
            bookId: bookId,
            bookTitle: bookTitle,
            taskTitle: Self.batchTaskTitle(for: initialProgress),
            session: session
        )
        let messageId = context.assistantMsgId
        updateRun(bookId) { $0.batchProgress = initialProgress; $0.batchExtractedNames = context.names }
        updateMessage(messageId, bookId: bookId) { $0.isStreaming = true }

        tasks[bookId] = Task { [weak self] in
            do {
                let outcome = try await AINameExtractionBatchProcessor.shared.retryFailedBatches(
                    context.failedBatches,
                    existingNames: context.names,
                    config: context.config,
                    promptOverride: context.promptOverride,
                    sessionId: context.sessionId,
                    resume: context.resume
                ) { progress, partial in
                    // Danh sách báo về đã gộp sẵn với tên cũ ⇒ tin kết quả không mất tên trong lúc thử lại.
                    let decorated = partial.map { AIBookDataInspector.shared.decorateExtractedNames(names: $0, bookId: bookId) }
                    Task { @MainActor [weak self] in
                        guard let self = self, self.isCurrentRun(runId, bookId: bookId) else { return }
                        self.applyBatchProgress(progress, names: decorated, bookId: bookId, assistantMsgId: messageId)
                        if let decorated {
                            self.persistNameScanProgress(progress, bookId: bookId)
                            self.syncNameScanRetry(names: decorated, bookId: bookId)
                        }
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
                    guard let self = self, self.isCurrentRun(runId, bookId: bookId) else { return }
                    self.writeNames(finalResults, toMessage: messageId, bookId: bookId)
                    self.persistNameScanProgress(outcome.progress, bookId: bookId)
                    var remaining = context
                    remaining.names = finalResults
                    remaining.failedBatches = outcome.failedBatches
                    self.setNameScanRetry(outcome.failedBatches.isEmpty ? nil : remaining, bookId: bookId)
                    let isPresented = self.presentedAIBookId == bookId
                    self.endRun(bookId: bookId)
                    onComplete(finalResults)
                    self.showRetryCompletionToast(
                        nameCount: finalResults.count,
                        stillFailed: outcome.failedBatches,
                        retriedCount: context.failedBatches.count,
                        bookTitle: bookTitle,
                        isPresented: isPresented
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self = self, self.isCurrentRun(runId, bookId: bookId) else { return }
                    // Giữ nguyên nội dung tin (danh sách đã gộp tới lúc dừng) và các lượt lỗi cũ: lần bấm sau gộp lại
                    // từ danh sách đã lưu nên không cộng trùng số lần xuất hiện.
                    self.updateMessage(messageId, bookId: bookId) { $0.isStreaming = false }
                    self.saveRunSession(bookId: bookId)
                    let toast = self.toastText(
                        "Thử lại lượt lỗi bị gián đoạn: \(error.localizedDescription)",
                        bookId: bookId,
                        bookTitle: bookTitle
                    )
                    self.endRun(bookId: bookId)
                    ToastManager.shared.show(message: toast, type: .error)
                }
            }
        }
        return true
    }

    /// Sau mỗi lượt của lần thử lại (1.3.602): context trong RAM theo kịp phần vừa lưu — danh sách tên đã gộp, bỏ các
    /// lượt mà bộ theo dõi điểm tiếp nối ghi là đã thành công. Không làm vậy thì lần thử lại bị dừng giữa chừng để lại
    /// context cũ: lần bấm sau gộp từ danh sách tên cũ (mất tên của lượt vừa xong) trong khi điểm tiếp nối đã vượt qua
    /// lượt đó. Lối ra bình thường vẫn thay context bằng kết quả cuối như cũ.
    func syncNameScanRetry(names: [AIExtractedName], bookId: String) {
        guard var context = nameScanRetryContexts[bookId] else { return }
        context.names = names
        if let resume = context.resume {
            context.failedBatches.removeAll { resume.isSucceeded(turnIndex: $0.turnIndex) }
        }
        setNameScanRetry(context.failedBatches.isEmpty ? nil : context, bookId: bookId)
    }

    /// Còn lượt lỗi ⇒ toast lỗi kể cả khi màn AI đang mở (nút vẫn còn, nhãn đổi số). Hết lỗi ⇒ toast thành công
    /// như quét thường: chỉ khi màn AI của truyện này đóng (mở thì nút biến mất và tin đã cập nhật).
    private func showRetryCompletionToast(
        nameCount: Int,
        stillFailed: [AINameScanFailedBatch],
        retriedCount: Int,
        bookTitle: String,
        isPresented: Bool
    ) {
        let suffix = isPresented || bookTitle.isEmpty ? "" : " · \(bookTitle)"
        if let first = stillFailed.first {
            ToastManager.shared.show(
                message: "Thử lại xong \(retriedCount) lượt: \(nameCount) tên riêng · còn \(stillFailed.count)/\(first.totalTurns) lượt lỗi\(suffix)",
                type: .error
            )
        } else if !isPresented {
            ToastManager.shared.show(message: "Thử lại xong, đã đủ \(nameCount) tên riêng!\(suffix)", type: .success)
        }
    }
}
