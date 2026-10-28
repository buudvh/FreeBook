import Foundation

/// Luồng quét tên riêng nhiều chương của `AIRuntimeCoordinator` — tách khỏi file gốc (sát trần 400 dòng) theo mẫu
/// `X+Feature.swift` (1.3.524). Nút "Thử lại k lượt lỗi" nằm ở `+NameScanRetry.swift` (1.3.527) và dùng chung các
/// helper `internal` ở cuối file này. Từ 1.3.558 mọi trạng thái của lượt quét nằm trong entry của đúng truyện
/// (`runs[bookId]`), so mã lượt theo truyện (`isCurrentRun`).
extension AIRuntimeCoordinator {
    /// Bắt đầu quét tên riêng các chương đã tải (batch), có thể giới hạn phạm vi và số chương.
    /// `session` khác nil ⇒ Gemini Web (bật lưu lịch sử) quét nối tiếp đúng cuộc chat Gemini của phiên này.
    /// `onProgress` nhận danh sách tên `nil` khi chỉ đổi tiến độ (báo "đang gửi lượt N"), tên giữ nguyên.
    /// Lượt vẫn lỗi sau vòng tự thử lại được giữ trong RAM (`nameScanRetryContexts`) cho nút "Thử lại k lượt lỗi".
    /// `translatesChapterTitles`/`convertsTraditionalToSimplified`: cấu hình dịch tên chương của màn AI (như Reader) —
    /// dải tiến độ hiện tên chương của lượt đang gửi theo đó; nút "Thử lại" dùng lại cấu hình này.
    public func startBatchExtraction(
        bookId: String,
        bookTitle: String,
        config: AIConfiguration,
        promptOverride: String? = nil,
        fromChapterIndex: Int? = nil,
        limit: Int? = nil,
        session: AIChatSession? = nil,
        assistantMsgId: UUID? = nil,
        translatesChapterTitles: Bool = false,
        convertsTraditionalToSimplified: Bool = false,
        onProgress: @escaping (AINameScanProgress, [AIExtractedName]?) -> Void,
        onComplete: @escaping ([AIExtractedName]) -> Void
    ) {
        // Lần quét mới thay lần cũ ⇒ bỏ các lượt lỗi còn giữ của lần trước (người dùng đã chọn: không giữ qua lần quét).
        // Phải gọi trước `beginRun`, vì `beginRun` giữ lại nút "Thử lại" của entry cũ.
        setNameScanRetry(nil, bookId: bookId)
        let initialProgress = AINameScanProgress()
        let runId = beginRun(
            bookId: bookId,
            bookTitle: bookTitle,
            taskTitle: Self.batchTaskTitle(for: initialProgress),
            session: session
        )
        updateRun(bookId) { $0.batchProgress = initialProgress }
        let sessionId = session?.id
        let chapterTitleStyle = AINameScanChapterTitleStyle(
            bookId: bookId,
            translatesTitles: translatesChapterTitles,
            convertsTraditionalToSimplified: convertsTraditionalToSimplified
        )

        tasks[bookId] = Task { [weak self] in
            do {
                let outcome = try await AINameExtractionBatchProcessor.shared.extractNamesFromDownloadedChapters(
                    bookId: bookId,
                    config: config,
                    promptOverride: promptOverride,
                    fromChapterIndex: fromChapterIndex,
                    limit: limit,
                    sessionId: sessionId,
                    chapterTitleStyle: chapterTitleStyle
                ) { progress, partial in
                    // Chỉ gắn cờ NE/VP khi danh sách tên đổi — báo "đang gửi lượt N" không kèm tên.
                    let decorated = partial.map { AIBookDataInspector.shared.decorateExtractedNames(names: $0, bookId: bookId) }
                    Task { @MainActor [weak self] in
                        // `Task.isCancelled` ở đây là của Task MỚI này (không bao giờ bị huỷ) ⇒ phải so mã lần chạy.
                        guard let self = self, self.isCurrentRun(runId, bookId: bookId) else { return }
                        self.applyBatchProgress(progress, names: decorated, bookId: bookId, assistantMsgId: assistantMsgId)
                        if decorated != nil {
                            self.persistNameScanProgress(progress, bookId: bookId)
                        }
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
                    // Lần chạy đã bị thay (dừng / lệnh mới của chính truyện này) thì đã được dọn — không ghi đè.
                    guard let self = self, self.isCurrentRun(runId, bookId: bookId) else { return }
                    self.writeNames(finalResults, toMessage: assistantMsgId, bookId: bookId)
                    self.persistNameScanProgress(outcome.progress, bookId: bookId)
                    if let mid = assistantMsgId, !outcome.failedBatches.isEmpty {
                        self.setNameScanRetry(NameScanRetryContext(
                            bookId: bookId,
                            config: config,
                            promptOverride: promptOverride,
                            sessionId: sessionId,
                            assistantMsgId: mid,
                            names: finalResults,
                            failedBatches: outcome.failedBatches,
                            resume: outcome.resume,
                            chapterTitleStyle: chapterTitleStyle
                        ), bookId: bookId)
                    }
                    let isPresented = self.presentedAIBookId == bookId
                    self.finishRun(bookId: bookId, outcome: .finished)
                    onComplete(finalResults)
                    self.showBatchCompletionToast(
                        nameCount: finalResults.count,
                        progress: outcome.progress,
                        bookTitle: bookTitle,
                        isPresented: isPresented
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self = self, self.isCurrentRun(runId, bookId: bookId) else { return }
                    // Dòng đầu ghi chương đã dừng (1.3.632) — đọc tiến độ trước `finishRun`; toast bên dưới vẫn giữ.
                    let stopNote = self.nameScanStopNote("Lọc name tự dừng", bookId: bookId)
                    let errorText = "\(stopNote)\nLỗi quét tên riêng: \(error.localizedDescription)"
                    // Dừng vì hạn mức/tài khoản giữa chừng (1.3.602): điểm tiếp nối đã ghi theo các lượt xong trước đó,
                    // nên tên của các lượt đó phải ở lại tin kết quả — lỗi thành một tin riêng. Chưa có tên ⇒ như cũ.
                    let scannedNames = self.runs[bookId]?.batchExtractedNames ?? []
                    if scannedNames.isEmpty {
                        self.updateMessage(assistantMsgId, bookId: bookId) {
                            $0.content = errorText
                            $0.isStreaming = false
                        }
                    } else {
                        self.writeNames(scannedNames, toMessage: assistantMsgId, bookId: bookId)
                        self.updateRun(bookId) { $0.session?.messages.append(AIChatMessage(role: .assistant, content: errorText)) }
                    }
                    self.saveRunSession(bookId: bookId)
                    // Lần quét tự dừng (hết hạn mức, mất đăng nhập, Google bắt xác minh…): toast chương đang lọc lúc
                    // dừng, kể cả khi màn AI đang mở — lý do chi tiết là tin lỗi ở trên. Đọc tiến độ trước `endRun`.
                    let toast = self.nameScanStopToast("Lọc name tự dừng", bookId: bookId, bookTitle: bookTitle)
                    self.finishRun(bookId: bookId, outcome: .failed)
                    ToastManager.shared.show(message: toast, type: .error)
                }
            }
        }
    }

    /// Ghi tiến độ của lượt quét hiện hành lên dải batch, tiêu đề trang "Tác vụ AI" và (khi tên đổi) tin trợ lý
    /// đang chạy — trong **một** lần ghi entry.
    func applyBatchProgress(_ progress: AINameScanProgress, names: [AIExtractedName]?, bookId: String, assistantMsgId: UUID?) {
        // Name người dùng đã ✕ trong tin này không được quay lại qua nhịp tiến độ (`+NameRemoval`).
        let keptNames = names.map { keepingUnremovedNames($0, messageId: assistantMsgId) }
        // Lần quét vừa chuyển sang Gemini Web vì Chế độ AI bị giới hạn (1.3.612): toast một lần, cả khi màn AI đang mở.
        if let switched = progress.switchedProviderName, runs[bookId]?.batchProgress?.switchedProviderName == nil {
            let bookTitle = runs[bookId]?.bookTitle ?? ""
            ToastManager.shared.show(
                message: toastText("Chế độ AI bị Google giới hạn — quét tiếp bằng \(switched)", bookId: bookId, bookTitle: bookTitle),
                type: .info
            )
        }
        updateRun(bookId) { state in
            state.batchProgress = progress
            state.taskTitle = Self.batchTaskTitle(for: progress)
            guard let keptNames else { return }
            state.batchExtractedNames = keptNames
            guard let mid = assistantMsgId, var session = state.session,
                  let index = session.messages.firstIndex(where: { $0.id == mid }) else { return }
            session.messages[index].content = keptNames.map { "\($0.original)=\($0.suggestedMeaning)" }.joined(separator: "\n")
            session.messages[index].isStreaming = true
            state.session = session
        }
    }

    /// Sau mỗi lượt và ở lối ra cuối (1.3.602): lưu phiên (tin kết quả đang giữ danh sách tên) **rồi mới** ghi điểm tiếp
    /// nối của lượt đó — thoát app giữa chừng thì điểm không bao giờ vượt quá phần tên đã lưu. Gọi sau `isCurrentRun`:
    /// lượt đã bị dừng/thay thì tên của nó bị bỏ, điểm cũng không được ghi. `resumeChapterIndex == nil` (chưa lượt nào
    /// xong) ⇒ giữ điểm cũ.
    func persistNameScanProgress(_ progress: AINameScanProgress, bookId: String) {
        saveRunSession(bookId: bookId)
        guard let resume = progress.resumeChapterIndex else { return }
        AINameScanScopeStore.shared.setResumeChapterIndex(resume, bookId: bookId)
    }

    /// Ghi danh sách `Tên=Nghĩa` cuối cùng vào tin kết quả và đánh dấu tin đã xong.
    func writeNames(_ names: [AIExtractedName], toMessage messageId: UUID?, bookId: String) {
        // Name người dùng đã ✕ trong tin này không được quay lại lúc ghi danh sách cuối (`+NameRemoval`).
        let keptNames = keepingUnremovedNames(names, messageId: messageId)
        let text = keptNames.map { "\($0.original)=\($0.suggestedMeaning)" }.joined(separator: "\n")
        updateMessage(messageId, bookId: bookId) {
            $0.content = text.isEmpty ? "Không có name" : text
            $0.isStreaming = false
        }
    }

    /// Có lượt lỗi ⇒ toast lỗi **kể cả khi màn AI đang mở**: tin kết quả chỉ giữ danh sách `Tên=Nghĩa` sạch để sao
    /// chép/duyệt, nên đây là chỗ duy nhất người dùng biết có lượt bị bỏ qua (cùng nút "Thử lại k lượt lỗi"). Từ 1.3.527
    /// số lượt lỗi là số lượt **vẫn** lỗi sau vòng tự thử lại. Không lỗi ⇒ toast thành công như cũ, chỉ khi màn AI của
    /// truyện này đóng. Màn AI của truyện này không mở ⇒ toast kèm tên truyện (1.3.558).
    private func showBatchCompletionToast(
        nameCount: Int,
        progress: AINameScanProgress,
        bookTitle: String,
        isPresented: Bool
    ) {
        let suffix = isPresented || bookTitle.isEmpty ? "" : " · \(bookTitle)"
        if progress.failedBatches > 0 {
            let detail = progress.isRetry ? "lượt vẫn lỗi sau khi thử lại" : "lượt lỗi đã bỏ qua"
            ToastManager.shared.show(
                message: "Đã quét xong \(nameCount) tên riêng · \(progress.failedBatches)/\(progress.totalBatches) \(detail)\(suffix)",
                type: .error
            )
        } else if !isPresented {
            ToastManager.shared.show(message: "Đã quét xong \(nameCount) tên riêng!\(suffix)", type: .success)
        }
    }

    /// Toast khi lần quét/thử lại dừng giữa chừng: `prefix` + chương của lượt đang gửi lúc dừng (" · ch.21–30: tên →
    /// tên", một chương " · ch.21: tên"); chưa gửi lượt nào ⇒ chỉ `prefix`. Màn AI của truyện không mở ⇒ kèm tên truyện
    /// (`toastText`). Gọi **trước** `endRun` — `endRun` dọn tiến độ của entry.
    func nameScanStopToast(_ prefix: String, bookId: String, bookTitle: String) -> String {
        let label = runs[bookId]?.batchProgress?.sendingChapterToastLabel
        return toastText(label.map { "\(prefix) · \($0)" } ?? prefix, bookId: bookId, bookTitle: bookTitle)
    }

    /// Câu ghi chương đã dừng cho **tin AI** (1.3.632): "`prefix` ở ch.21–30: tên → tên." (một chương "ở ch.21: tên.");
    /// chưa gửi lượt nào ⇒ "`prefix` khi đang chuẩn bị.". Tên chương đã kết bằng dấu câu ⇒ không thêm "." (tránh
    /// "Hà.."). Gọi **trước** `endRun` — `endRun` dọn tiến độ của entry.
    func nameScanStopNote(_ prefix: String, bookId: String) -> String {
        guard let label = runs[bookId]?.batchProgress?.sendingChapterToastLabel else {
            return "\(prefix) khi đang chuẩn bị."
        }
        let endsWithPunctuation = label.last.map { ".!?…".contains($0) } ?? false
        return "\(prefix) ở \(label)\(endsWithPunctuation ? "" : ".")"
    }

    /// Tiêu đề tác vụ — cùng nghĩa với dải tiến độ: N là lượt **đang gửi**, kèm khoảng chương của lượt đó
    /// (" · ch.21–30"); lúc chuẩn bị kèm số chương đã đọc (1.3.602).
    static func batchTaskTitle(for progress: AINameScanProgress) -> String {
        if progress.isPreparing {
            if progress.isRetry { return "Đang chuẩn bị thử lại..." }
            guard let count = progress.chapterCount else { return "Đang chuẩn bị quét..." }
            return "Đang chuẩn bị quét: đã đọc \(progress.preparedChapters)/\(count) chương"
        }
        let chapters = progress.sendingChapterRangeLabel.map { " · \($0)" } ?? ""
        // Đang chờ Chế độ AI hết giới hạn (1.3.612): tiến độ báo lại mỗi 15 s nên tiêu đề đếm ngược theo nhịp đó.
        if let remaining = progress.rateLimitRemainingSeconds() {
            return "Chờ Google \(GoogleAIModeError.clockText(seconds: remaining)) · Batch \(progress.sendingBatch)/\(progress.totalBatches)\(chapters)"
        }
        let verb = progress.isRetry ? "Đang thử lại" : "Đang quét"
        return "\(verb): Batch \(progress.sendingBatch)/\(progress.totalBatches)\(chapters)"
    }
}
