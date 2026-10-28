import SwiftUI

/// Các hàm xử lý tác vụ và logic tương tác của ReaderAIFullScreenView.
extension ReaderAIFullScreenView {
    internal func reloadSettings() {
        let config = AISettingsStore.shared.loadConfiguration()
        availableProfiles = config.profiles
        selectedProfileId = config.activeProfileId
        availableModels = config.activeProfile.availableModels
        if selectedModel.isEmpty || !availableModels.contains(selectedModel) {
            selectedModel = config.activeProfile.selectedModel
        }
        nameExtractionPromptForSheet = config.nameExtractionPrompt
    }

    internal func handleProfileChanged(_ newProfileId: String) {
        selectedProfileId = newProfileId
        if let profile = availableProfiles.first(where: { $0.id == newProfileId }) {
            availableModels = profile.availableModels
            selectedModel = profile.selectedModel.isEmpty ? (profile.availableModels.first ?? "") : profile.selectedModel
            currentSession.providerProfileId = newProfileId
            currentSession.model = selectedModel
            AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)
        }
    }

    internal func sendUserMessage(promptOverride: String? = nil) {
        let textToSend = (promptOverride ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty, !isStreaming else { return }

        inputText = ""
        let userMsg = AIChatMessage(role: .user, content: textToSend)
        currentSession.messages.append(userMsg)

        if currentSession.title == "Phiên chat mới" {
            currentSession.title = String(textToSend.prefix(24))
        }

        let assistantMsgId = UUID()
        let placeholderMsg = AIChatMessage(id: assistantMsgId, role: .assistant, content: "", isStreaming: true)
        currentSession.messages.append(placeholderMsg)
        AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)

        var config = AISettingsStore.shared.loadConfiguration()
        if let profile = config.profiles.first(where: { $0.id == selectedProfileId }) {
            config.activeProfileId = profile.id
        }
        config.selectedModel = selectedModel
        // Gemini Web + bật "Lưu chat vào lịch sử Gemini" (1.3.524), và Chế độ AI của Google (1.3.609): provider tự giữ
        // hội thoại của phiên ⇒ không gom tóm tắt ngữ cảnh cũ lẫn cửa sổ tin gần nhất vào prompt, kể cả khi phải mở cuộc
        // chat mới (provider không biết các lượt trước — đánh đổi đã chấp nhận).
        let geminiKeepsHistory = (config.activeProfile.isGeminiWeb && GeminiWebConversationStore.saveToHistory)
            || config.activeProfile.isGoogleAIMode

        // 1. Nạp từ điển Name riêng và VP riêng của truyện
        let bookDictContext = AIBookDataInspector.shared.fetchBookDictionaryContext(
            bookId: bookId,
            currentRawText: currentChapterRawContent
        )

        // 2. Nạp Trí nhớ tổng & Trí nhớ dài hạn của truyện
        let globalMem = BookAIMemoryStore.shared.loadGlobalMemory().trimmingCharacters(in: .whitespacesAndNewlines)
        let globalContext = globalMem.isEmpty ? "" : "\n\n[Trí nhớ tổng / Quy tắc AI toàn cục]:\n\(globalMem)"
        let bookMemory = BookAIMemoryStore.shared.loadMemory(for: bookId)
        let memoryContext = bookMemory.compiledContextText()

        // 3. Nạp Tóm tắt ngữ cảnh cũ của session nếu đã compact
        let summaryContext = (!geminiKeepsHistory && currentSession.contextSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? "\n\n[Tóm tắt ngữ cảnh các lượt trao đổi trước]:\n\(currentSession.contextSummary!)"
            : ""

        // 4. Nội dung raw của chương hiện tại
        let rawContext = currentChapterRawContent.isEmpty
            ? ""
            : "\n\nNội dung raw chương hiện tại:\n\(currentChapterRawContent.prefix(8000))"

        let systemInstruction = "\(config.systemPrompt)\nChế độ: \(selectedMode.title).\(globalContext)\(bookDictContext)\(memoryContext)\(summaryContext)\(rawContext)"
        var chatMessages: [OpenAIChatRequest.Message] = [
            OpenAIChatRequest.Message(role: "system", content: systemInstruction)
        ]

        // 5. Cửa sổ trượt tin nhắn hội thoại (nếu > 12 tin nhắn, gửi 6 tin nhắn gần nhất kèm summary).
        //    Gemini giữ lịch sử ⇒ chỉ gửi tin hiện tại.
        let messagesToSend = currentSession.messages.filter { $0.id != assistantMsgId }
        let recentMessages = geminiKeepsHistory
            ? [userMsg]
            : (messagesToSend.count > 6 ? Array(messagesToSend.suffix(6)) : messagesToSend)
        for m in recentMessages {
            chatMessages.append(OpenAIChatRequest.Message(role: m.role.rawValue, content: m.content))
        }

        isStreaming = true
        let sessionSnapshot = currentSession
        let configSnapshot = config

        AIRuntimeCoordinator.shared.startChatStreaming(
            config: config,
            messages: chatMessages,
            session: currentSession,
            bookId: bookId,
            bookTitle: bookTitle,
            assistantMsgId: assistantMsgId,
            onDelta: { [self] (delta: String) in
                Task { @MainActor in
                    if let idx = self.currentSession.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        self.currentSession.messages[idx].content = delta
                    }
                }
            },
            onComplete: { [self] (finalContent: String) in
                Task { @MainActor in
                    if let idx = self.currentSession.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        self.currentSession.messages[idx].isStreaming = false

                        self.currentSession.messages[idx].content = finalContent
                    }
                    self.isStreaming = false
                    self.currentSession.updatedAt = Date()
                    AIChatHistoryStore.shared.saveSession(self.currentSession, for: self.bookId)

                    // Tự động kiểm tra và compact ngữ cảnh nền nếu vượt ngưỡng
                    Task.detached {
                        if let newSummary = await AIContextCompactor.shared.compactSessionIfNeeded(
                            session: sessionSnapshot,
                            config: configSnapshot
                        ) {
                            await MainActor.run {
                                if self.currentSession.id == sessionSnapshot.id {
                                    self.currentSession.contextSummary = newSummary
                                    AIChatHistoryStore.shared.saveSession(self.currentSession, for: self.bookId)
                                }
                            }
                        }
                    }
                }
            },
            onError: { [self] (errorDesc: String) in
                Task { @MainActor in
                    if let idx = self.currentSession.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        self.currentSession.messages[idx].content = "Lỗi phản hồi: \(errorDesc)"
                        self.currentSession.messages[idx].isStreaming = false
                    }
                    self.isStreaming = false
                }
            }
        )
    }

    /// Profile đang chọn trên màn AI là Chế độ AI của Google (1.3.609) — khoá chip "Dịch mượt raw".
    internal var isGoogleAIModeSelected: Bool {
        availableProfiles.first(where: { $0.id == selectedProfileId })?.isGoogleAIMode == true
    }

    internal func stopStreaming() {
        let stopNote = AIRuntimeCoordinator.shared.stopActiveTask(bookId: bookId)
        isStreaming = false
        for index in currentSession.messages.indices where currentSession.messages[index].isStreaming {
            currentSession.messages[index].isStreaming = false
            if currentSession.messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentSession.messages[index].content = "Đã dừng."
            }
        }
        appendStopNote(stopNote)
    }

    /// Dừng lúc đang lọc name nhiều chương ⇒ coordinator đã thêm tin AI ghi chương đã dừng vào phiên của nó (1.3.632);
    /// màn giữ phiên riêng trong `@State` nên thêm đúng tin đó vào phiên đang hiện. Chat thường ⇒ `nil`, không thêm gì.
    private func appendStopNote(_ stopNote: String?) {
        guard let stopNote else { return }
        currentSession.messages.append(AIChatMessage(role: .assistant, content: stopNote))
    }

    internal func handleQuickAction(_ type: ReaderAIQuickActionChipsView.ActionType) {
        // Chip đã mờ và khoá khi có lệnh chạy; chặn thêm ở đây (phòng thủ) — chip "nhiều chương" từng mở sheet bất kể
        // đang chạy, rồi bắt đầu quét là huỷ lệnh đang chạy.
        guard !isStreaming, !isBatchExtracting else { return }
        switch type {
        case .summarizeChapter:
            sendUserMessage(promptOverride: "Tóm tắt ngắn gọn các sự kiện và nhân vật chính trong chương này.")
        case .extractNamesCurrentChapter:
            sendUserMessage(promptOverride: "Lọc tên riêng trong chương này")
        case .extractNamesAllDownloaded:
            showingBatchPromptSheet = true
        case .explainContextAndCharacters:
            sendUserMessage(promptOverride: "Giải thích bối cảnh, các thế lực và nhân vật xuất hiện trong chương này.")
        case .translateSmoothly:
            // Chế độ AI của Google chỉ tóm lược, không dịch đủ (1.3.609) — chip đã khoá, chặn thêm ở đây.
            guard !isGoogleAIModeSelected else { return }
            sendUserMessage(promptOverride: "Dịch lại toàn bộ nội dung chương này theo văn phong mượt mà, thuần Việt, tự nhiên.")
        }
    }

    /// Chạy quét batch với prompt, chương bắt đầu (`nil` = từ chương đã tải đầu tiên) và số chương người dùng đã chọn
    /// trong sheet (1.3.602).
    internal func beginBatchExtraction(with prompt: String, fromChapterIndex: Int?, limit: Int?) {
        startBatchExtraction(promptOverride: prompt, fromChapterIndex: fromChapterIndex, limit: limit)
    }

    internal func startBatchExtraction(promptOverride: String? = nil, fromChapterIndex: Int? = nil, limit: Int? = nil) {
        // Đang chat stream thì không bắt đầu quét: `AIRuntimeCoordinator.startBatchExtraction` thay tác vụ đang chạy của
        // truyện này, sẽ huỷ ngang câu trả lời đang chạy.
        guard !isBatchExtracting, !isStreaming else { return }
        isBatchExtracting = true
        batchProgress = AINameScanProgress()
        batchExtractedNames.removeAll()

        // Nhãn phạm vi: số chương hiển thị đánh từ 1 như mọi chỗ khác; thêm số chương khi có giới hạn (1.3.602).
        let scopeLabel: String
        if let from = fromChapterIndex {
            scopeLabel = limit.map { "\($0) chương từ ch.\(from + 1)" } ?? "từ ch.\(from + 1)"
        } else {
            scopeLabel = limit.map { "\($0) chương đã tải" } ?? "toàn bộ chương đã tải"
        }
        let userMsg = AIChatMessage(role: .user, content: "Quét tên riêng \(scopeLabel)")
        currentSession.messages.append(userMsg)

        let msgId = UUID()
        // Khởi tạo content rỗng để hiển thị "AI đang suy nghĩ" trong timeline
        currentSession.messages.append(AIChatMessage(id: msgId, role: .assistant, content: "", isStreaming: true))
        AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)
        isStreaming = true

        var config = AISettingsStore.shared.loadConfiguration()
        if let profile = config.profiles.first(where: { $0.id == selectedProfileId }) {
            config.activeProfileId = profile.id
        }
        config.selectedModel = selectedModel

        AIRuntimeCoordinator.shared.startBatchExtraction(
            bookId: bookId,
            bookTitle: bookTitle,
            config: config,
            promptOverride: promptOverride,
            fromChapterIndex: fromChapterIndex,
            limit: limit,
            session: currentSession,
            assistantMsgId: msgId,
            translatesChapterTitles: translatesChapterTitles,
            convertsTraditionalToSimplified: convertsTraditionalToSimplified,
            onProgress: { [self] (progress: AINameScanProgress, partial: [AIExtractedName]?) in
                Task { @MainActor in self.applyNameScanProgress(progress, partial: partial, messageId: msgId) }
            },
            onComplete: { [self] (finalResults: [AIExtractedName]) in
                Task { @MainActor in self.finishNameScan(finalResults, messageId: msgId) }
            }
        )
    }

    /// Nút "Thử lại k lượt lỗi" (1.3.527): chạy lại các lượt còn lỗi của lần quét gần nhất, ghi đè đúng tin kết quả
    /// cũ. Cùng cách hiển thị với quét thường: tin chạy, dải tiến độ ("Đang thử lại"), nút dừng là `cancelBatchExtraction`.
    internal func retryFailedNameScanBatches() {
        guard !isBatchExtracting, !isStreaming, let retry = nameScanRetry else { return }
        let msgId = retry.messageId
        var session = currentSession
        if let idx = session.messages.firstIndex(where: { $0.id == msgId }) {
            session.messages[idx].isStreaming = true
        }
        let started = AIRuntimeCoordinator.shared.retryFailedNameScanBatches(
            bookId: bookId,
            bookTitle: bookTitle,
            session: session,
            onProgress: { [self] (progress: AINameScanProgress, partial: [AIExtractedName]?) in
                Task { @MainActor in self.applyNameScanProgress(progress, partial: partial, messageId: msgId) }
            },
            onComplete: { [self] (finalResults: [AIExtractedName]) in
                Task { @MainActor in self.finishNameScan(finalResults, messageId: msgId) }
            }
        )
        guard started else { return }
        currentSession = session
        isBatchExtracting = true
        isStreaming = true
        batchProgress = AIRuntimeCoordinator.shared.run(for: bookId)?.batchProgress
    }

    /// Tiến độ quét/thử lại: dải batch + (khi danh sách tên đổi) tin kết quả đang chạy.
    private func applyNameScanProgress(_ progress: AINameScanProgress, partial: [AIExtractedName]?, messageId: UUID) {
        batchProgress = progress
        // `nil` = chỉ báo "đang gửi lượt N", danh sách tên chưa đổi ⇒ không vẽ lại tin dài.
        guard let partial else { return }
        batchExtractedNames = partial
        let text = partial.map { "\($0.original)=\($0.suggestedMeaning)" }.joined(separator: "\n")
        if let idx = currentSession.messages.firstIndex(where: { $0.id == messageId }) {
            currentSession.messages[idx].content = text
            currentSession.messages[idx].isStreaming = true
        }
    }

    /// Quét/thử lại xong: tắt trạng thái chạy, ghi danh sách cuối vào tin kết quả và lưu phiên.
    private func finishNameScan(_ finalResults: [AIExtractedName], messageId: UUID) {
        isBatchExtracting = false
        isStreaming = false
        batchProgress = nil
        batchExtractedNames = finalResults
        let text = finalResults.map { "\($0.original)=\($0.suggestedMeaning)" }.joined(separator: "\n")
        if let idx = currentSession.messages.firstIndex(where: { $0.id == messageId }) {
            currentSession.messages[idx].content = text.isEmpty ? "Không có name" : text
            currentSession.messages[idx].isStreaming = false
        }
        AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)
    }

    internal func cancelBatchExtraction() {
        let stopNote = AIRuntimeCoordinator.shared.stopActiveTask(bookId: bookId)
        isBatchExtracting = false
        isStreaming = false
        batchProgress = nil
        for index in currentSession.messages.indices where currentSession.messages[index].isStreaming {
            currentSession.messages[index].isStreaming = false
            if currentSession.messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentSession.messages[index].content = "Đã dừng."
            }
        }
        appendStopNote(stopNote)
    }

    internal func saveNamesToDictionary(_ items: [AIExtractedName], isName: Bool, isMerge: Bool) {
        let header = "Đã lưu \(items.count) tên riêng vào từ điển \(isName ? "Name riêng" : "VietPhrase riêng"):"
        let plainText = condenseExtractedNamesToText(names: items, title: header)

        for i in currentSession.messages.indices {
            if currentSession.messages[i].extractedNames != nil {
                currentSession.messages[i].content = plainText
                currentSession.messages[i].extractedNames = nil
            }
        }
        batchExtractedNames.removeAll()
        AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)

        Task {
            let savedCount = await AIHarnessService.shared.saveExtractedEntries(items, bookId: bookId, isName: isName, isMerge: isMerge)
            await MainActor.run {
                let targetName = isName ? "Name riêng" : "VietPhrase riêng"
                if savedCount > 0 {
                    ToastManager.shared.show(message: "Đã lưu \(savedCount) mục vào \(targetName) của truyện", type: .success)
                } else {
                    ToastManager.shared.show(message: "Lưu vào \(targetName) thất bại", type: .error)
                }
            }
        }
    }

    internal func approveAction(_ action: AIHarnessAction) {
        Task {
            _ = try? await AIHarnessService.shared.executeAction(action, bookId: bookId)
        }
    }

    internal func rejectAction(_ action: AIHarnessAction) {}

    internal func approveAllActions(_ actions: [AIHarnessAction]) {
        for action in actions where action.status == .pendingReview {
            approveAction(action)
        }
    }
}
