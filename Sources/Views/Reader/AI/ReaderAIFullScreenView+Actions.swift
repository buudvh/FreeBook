import SwiftUI

/// Các hàm xử lý tác vụ và logic tương tác của ReaderAIFullScreenView.
extension ReaderAIFullScreenView {
    internal func initializeSession() {
        reloadSettings()
        let sessions = AIChatHistoryStore.shared.loadSessions(for: bookId)
        if let first = sessions.first {
            switchToSession(first)
        } else {
            startNewChat()
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
        streamingTask = Task {
            do {
                let stream = OpenAIClient.shared.sendChatStreaming(config: config, messages: chatMessages)
                var accumulated = ""
                for try await delta in stream {
                    accumulated += delta
                    await MainActor.run {
                        if let idx = currentSession.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                            currentSession.messages[idx].content = accumulated
                        }
                    }
                }
                await MainActor.run {
                    if let idx = currentSession.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        currentSession.messages[idx].isStreaming = false
                    }
                    isStreaming = false
                    currentSession.updatedAt = Date()
                    AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)
                }

                // Tự động kiểm tra và compact ngữ cảnh nền nếu vượt ngưỡng
                let sessionSnapshot = currentSession
                let configSnapshot = config
                Task.detached {
                    if let newSummary = await AIContextCompactor.shared.compactSessionIfNeeded(session: sessionSnapshot, config: configSnapshot) {
                        await MainActor.run {
                            if self.currentSession.id == sessionSnapshot.id {
                                self.currentSession.contextSummary = newSummary
                                AIChatHistoryStore.shared.saveSession(self.currentSession, for: self.bookId)
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = currentSession.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        currentSession.messages[idx].content = "Lỗi phản hồi: \(error.localizedDescription)"
                        currentSession.messages[idx].isStreaming = false
                    }
                    isStreaming = false
                }
            }
        }
    }

    internal func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
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
        currentSession.messages.append(AIChatMessage(id: msgId, role: .assistant, content: "Đang phân tích tên riêng từ nội dung raw chương...", isStreaming: true))

        Task {
            do {
                let names = try await AINameExtractionBatchProcessor.shared.extractNamesFromText(
                    text: currentChapterRawContent,
                    config: config
                )
                await MainActor.run {
                    if let idx = currentSession.messages.firstIndex(where: { $0.id == msgId }) {
                        currentSession.messages[idx].content = "Đã tìm thấy \(names.count) tên riêng trong chương này:"
                        currentSession.messages[idx].extractedNames = names
                        currentSession.messages[idx].isStreaming = false
                    }
                    AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)
                }
            } catch {
                await MainActor.run {
                    if let idx = currentSession.messages.firstIndex(where: { $0.id == msgId }) {
                        currentSession.messages[idx].content = "Lỗi lọc tên riêng: \(error.localizedDescription)"
                        currentSession.messages[idx].isStreaming = false
                    }
                }
            }
        }
    }

    internal func startBatchExtraction() {
        guard !isBatchExtracting else { return }
        isBatchExtracting = true
        batchProgress = (0, 1)
        batchExtractedNames.removeAll()

        var config = AISettingsStore.shared.loadConfiguration()
        if let profile = config.profiles.first(where: { $0.id == selectedProfileId }) {
            config.activeProfileId = profile.id
        }
        config.selectedModel = selectedModel

        batchExtractionTask = Task {
            do {
                let results = try await AINameExtractionBatchProcessor.shared.extractNamesFromDownloadedChapters(
                    bookId: bookId,
                    config: config
                ) { current, total, partial in
                    Task { @MainActor in
                        self.batchProgress = (current, total)
                        self.batchExtractedNames = partial
                    }
                }
                await MainActor.run {
                    self.isBatchExtracting = false
                    self.batchExtractedNames = results
                }
            } catch {
                await MainActor.run {
                    self.isBatchExtracting = false
                }
            }
        }
    }

    internal func cancelBatchExtraction() {
        batchExtractionTask?.cancel()
        batchExtractionTask = nil
        isBatchExtracting = false
    }

    internal func saveNamesToDictionary(_ items: [AIExtractedName], isName: Bool, isMerge: Bool) {
        Task {
            let saved = await AIHarnessService.shared.saveExtractedEntries(items, bookId: bookId, isName: isName, isMerge: isMerge)
            await MainActor.run {
                let targetTitle = isName ? "Name riêng" : "VP riêng"
                ToastManager.shared.show("Đã lưu \(saved) mục vào \(targetTitle) của truyện")
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
