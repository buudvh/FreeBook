import SwiftUI

/// Các hàm xử lý tác vụ và logic tương tác của ReaderAIFullScreenView.
extension ReaderAIFullScreenView {
    internal func initializeSession() {
        reloadSettings()
        let sessions = AIChatHistoryStore.shared.loadSessions(for: bookId)
        if let activeId = AIRuntimeCoordinator.shared.activeSessionId,
           let activeSession = sessions.first(where: { $0.id == activeId }) {
            switchToSession(activeSession)
        } else if let first = sessions.first {
            switchToSession(first)
        } else {
            startNewChat()
        }

        if AIRuntimeCoordinator.shared.isRunning {
            isStreaming = true
            if let progress = AIRuntimeCoordinator.shared.batchProgress {
                isBatchExtracting = true
                batchProgress = progress
                batchExtractedNames = AIRuntimeCoordinator.shared.batchExtractedNames
            }
        }
    }

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

    internal func startNewChat() {
        let config = AISettingsStore.shared.loadConfiguration()
        availableProfiles = config.profiles
        selectedProfileId = config.activeProfileId
        availableModels = config.activeProfile.availableModels
        selectedModel = config.activeProfile.selectedModel

        let newSession = AIChatSession(
            bookId: bookId,
            title: "Phiên chat mới",
            mode: selectedMode,
            model: selectedModel,
            providerProfileId: selectedProfileId
        )
        currentSession = newSession
        currentSessionId = newSession.id
        batchExtractedNames.removeAll()
        AIChatHistoryStore.shared.saveSession(newSession, for: bookId)
    }

    internal func switchToSession(_ session: AIChatSession) {
        currentSession = session
        currentSessionId = session.id
        selectedMode = session.mode

        let config = AISettingsStore.shared.loadConfiguration()
        availableProfiles = config.profiles
        let profileId = session.providerProfileId ?? config.activeProfileId
        selectedProfileId = profileId

        if let profile = availableProfiles.first(where: { $0.id == profileId }) {
            availableModels = profile.availableModels
        } else {
            availableModels = config.activeProfile.availableModels
        }
        selectedModel = session.model
    }

    internal func sendUserMessage(promptOverride: String? = nil) {
        let textToSend = (promptOverride ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty, !isStreaming else { return }

        // Nhận diện ý định tự gõ lệnh lọc tên riêng
        let lower = textToSend.lowercased()
        if lower.contains("lọc tên riêng") || lower.contains("loc ten rieng") || lower.contains("trích xuất tên riêng") || lower.contains("trich xuat ten") {
            inputText = ""
            extractNamesCurrentChapter()
            return
        }

        inputText = ""
        let userMsg = AIChatMessage(role: .user, content: textToSend)
        currentSession.messages.append(userMsg)

        if currentSession.title == "Phiên chat mới" {
            currentSession.title = String(textToSend.prefix(24))
        }

        let assistantMsgId = UUID()
        let placeholderMsg = AIChatMessage(id: assistantMsgId, role: .assistant, content: "", isStreaming: true)
        currentSession.messages.append(placeholderMsg)

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

        // 2. Nạp Trí nhớ dài hạn của truyện
        let bookMemory = BookAIMemoryStore.shared.loadMemory(for: bookId)
        let memoryContext = bookMemory.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\n\n[Trí nhớ bối cảnh & nhân vật của truyện]:\n\(bookMemory.notes)"

        // 3. Nạp Tóm tắt ngữ cảnh cũ của session nếu đã compact
        let summaryContext = (currentSession.contextSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? "\n\n[Tóm tắt ngữ cảnh các lượt trao đổi trước]:\n\(currentSession.contextSummary!)"
            : ""

        // 4. Nội dung raw của chương hiện tại
        let rawContext = currentChapterRawContent.isEmpty
            ? ""
            : "\n\nNội dung raw chương hiện tại:\n\(currentChapterRawContent.prefix(8000))"

        let systemInstruction = "\(config.systemPrompt)\nChế độ: \(selectedMode.title).\(bookDictContext)\(memoryContext)\(summaryContext)\(rawContext)"
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
                        self.currentSession.messages[idx].content = finalContent
                        self.currentSession.messages[idx].isStreaming = false
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
            extractNamesCurrentChapter()
        case .extractNamesAllDownloaded:
            startBatchExtraction()
        case .explainContextAndCharacters:
            sendUserMessage(promptOverride: "Giải thích bối cảnh, các thế lực và nhân vật xuất hiện trong chương này.")
        case .translateSmoothly:
            sendUserMessage(promptOverride: "Dịch lại toàn bộ nội dung chương này theo văn phong mượt mà, thuần Việt, tự nhiên.")
        }
    }

    internal func extractNamesCurrentChapter() {
        let userMsg = AIChatMessage(role: .user, content: "Lọc tên riêng trong chương này")
        currentSession.messages.append(userMsg)

        var config = AISettingsStore.shared.loadConfiguration()
        if let profile = config.profiles.first(where: { $0.id == selectedProfileId }) {
            config.activeProfileId = profile.id
        }
        config.selectedModel = selectedModel

        let msgId = UUID()
        // Khởi tạo content rỗng để message.content.isEmpty && message.isStreaming hiển thị "AI đang suy nghĩ"
        currentSession.messages.append(AIChatMessage(id: msgId, role: .assistant, content: "", isStreaming: true))
        isStreaming = true

        AIRuntimeCoordinator.shared.startExtractNamesCurrentChapter(
            bookId: bookId,
            rawContent: currentChapterRawContent,
            config: config,
            onComplete: { [self] (names: [AIExtractedName]) in
                Task { @MainActor in
                    if let idx = self.currentSession.messages.firstIndex(where: { $0.id == msgId }) {
                        self.currentSession.messages[idx].content = "Đã tìm thấy \(names.count) tên riêng trong chương này:"
                        self.currentSession.messages[idx].extractedNames = names
                        self.currentSession.messages[idx].isStreaming = false
                    }
                    self.isStreaming = false
                    AIChatHistoryStore.shared.saveSession(self.currentSession, for: self.bookId)
                }
            },
            onError: { [self] (errorDesc: String) in
                Task { @MainActor in
                    if let idx = self.currentSession.messages.firstIndex(where: { $0.id == msgId }) {
                        self.currentSession.messages[idx].content = "Lỗi lọc tên riêng: \(errorDesc)"
                        self.currentSession.messages[idx].isStreaming = false
                    }
                    self.isStreaming = false
                }
            }
        )
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
        isStreaming = true

        var config = AISettingsStore.shared.loadConfiguration()
        if let profile = config.profiles.first(where: { $0.id == selectedProfileId }) {
            config.activeProfileId = profile.id
        }
        config.selectedModel = selectedModel

        AIRuntimeCoordinator.shared.startBatchExtraction(
            bookId: bookId,
            config: config,
            onProgress: { [self] (current: Int, total: Int, partial: [AIExtractedName]) in
                Task { @MainActor in
                    self.batchProgress = (current, total)
                    self.batchExtractedNames = partial
                }
            },
            onComplete: { [self] (finalResults: [AIExtractedName]) in
                Task { @MainActor in
                    self.isBatchExtracting = false
                    self.isStreaming = false
                    self.batchExtractedNames = finalResults
                    if let idx = self.currentSession.messages.firstIndex(where: { $0.id == msgId }) {
                        self.currentSession.messages[idx].content = "Đã quét xong \(finalResults.count) tên riêng từ các chương đã tải:"
                        self.currentSession.messages[idx].extractedNames = finalResults
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
        Task {
            _ = await AIHarnessService.shared.saveExtractedEntries(items, bookId: bookId, isName: isName, isMerge: isMerge)
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
