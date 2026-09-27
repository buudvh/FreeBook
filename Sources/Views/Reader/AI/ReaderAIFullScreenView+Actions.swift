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
        AIRuntimeCoordinator.shared.activeSession = currentSession

        var config = AISettingsStore.shared.loadConfiguration()
        if let profile = config.profiles.first(where: { $0.id == selectedProfileId }) {
            config.activeProfileId = profile.id
        }
        config.selectedModel = selectedModel

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
        let summaryContext = (currentSession.contextSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
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

        // 5. Cửa sổ trượt tin nhắn hội thoại (nếu > 12 tin nhắn, gửi 6 tin nhắn gần nhất kèm summary)
        let messagesToSend = currentSession.messages.filter { $0.id != assistantMsgId }
        let recentMessages = messagesToSend.count > 6 ? Array(messagesToSend.suffix(6)) : messagesToSend
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

    internal func stopStreaming() {
        AIRuntimeCoordinator.shared.cancelActiveTask()
        isStreaming = false
        if let lastIdx = currentSession.messages.indices.last {
            currentSession.messages[lastIdx].isStreaming = false
        }
    }

    internal func handleQuickAction(_ type: ReaderAIQuickActionChipsView.ActionType) {
        switch type {
        case .summarizeChapter:
            sendUserMessage(promptOverride: "Tóm tắt ngắn gọn các sự kiện và nhân vật chính trong chương này.")
        case .extractNamesCurrentChapter:
            sendUserMessage(promptOverride: "Lọc tên riêng trong chương này")
        case .extractNamesAllDownloaded:
            startBatchExtraction()
        case .explainContextAndCharacters:
            sendUserMessage(promptOverride: "Giải thích bối cảnh, các thế lực và nhân vật xuất hiện trong chương này.")
        case .translateSmoothly:
            sendUserMessage(promptOverride: "Dịch lại toàn bộ nội dung chương này theo văn phong mượt mà, thuần Việt, tự nhiên.")
        }
    }

    internal func startBatchExtraction() {
        guard !isBatchExtracting else { return }
        isBatchExtracting = true
        batchProgress = (0, 1)
        batchExtractedNames.removeAll()

        let userMsg = AIChatMessage(role: .user, content: "Quét tên riêng toàn bộ chương đã tải")
        currentSession.messages.append(userMsg)

        let msgId = UUID()
        // Khởi tạo content rỗng để hiển thị "AI đang suy nghĩ" trong timeline
        currentSession.messages.append(AIChatMessage(id: msgId, role: .assistant, content: "", isStreaming: true))
        AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)
        AIRuntimeCoordinator.shared.activeSession = currentSession
        isStreaming = true

        var config = AISettingsStore.shared.loadConfiguration()
        if let profile = config.profiles.first(where: { $0.id == selectedProfileId }) {
            config.activeProfileId = profile.id
        }
        config.selectedModel = selectedModel

        AIRuntimeCoordinator.shared.startBatchExtraction(
            bookId: bookId,
            config: config,
            session: currentSession,
            assistantMsgId: msgId,
            onProgress: { [self] (current: Int, total: Int, partial: [AIExtractedName]) in
                Task { @MainActor in
                    self.batchProgress = (current, total)
                    self.batchExtractedNames = partial
                    let text = partial.map { "\($0.original)=\($0.suggestedMeaning)" }.joined(separator: "\n")
                    if let idx = self.currentSession.messages.firstIndex(where: { $0.id == msgId }) {
                        self.currentSession.messages[idx].content = text
                        self.currentSession.messages[idx].isStreaming = true
                    }
                }
            },
            onComplete: { [self] (finalResults: [AIExtractedName]) in
                Task { @MainActor in
                    self.isBatchExtracting = false
                    self.isStreaming = false
                    self.batchExtractedNames = finalResults
                    let text = finalResults.map { "\($0.original)=\($0.suggestedMeaning)" }.joined(separator: "\n")
                    if let idx = self.currentSession.messages.firstIndex(where: { $0.id == msgId }) {
                        self.currentSession.messages[idx].content = text.isEmpty ? "Không có name" : text
                        self.currentSession.messages[idx].isStreaming = false
                    }
                    AIChatHistoryStore.shared.saveSession(self.currentSession, for: self.bookId)
                }
            }
        )
    }

    internal func cancelBatchExtraction() {
        AIRuntimeCoordinator.shared.cancelActiveTask()
        isBatchExtracting = false
        isStreaming = false
        batchProgress = nil
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
