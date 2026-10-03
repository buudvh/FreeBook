import SwiftUI

/// Các hàm xử lý tải phiên chat, phân trang lazy loading và nén danh sách tên riêng.
extension ReaderAIFullScreenView {
    /// Nạp phiên chat bất đồng bộ ở background thread, hiển thị Skeleton tức thì để bảo vệ TTS.
    internal func initializeSessionAsync() {
        reloadSettings()
        isLoadingSession = true

        let bid = bookId
        Task.detached(priority: .utility) {
            BookAIMemoryStore.shared.syncWithBookData(bookId: bid)
        }

        if let active = AIRuntimeCoordinator.shared.activeSession, active.bookId == bookId {
            var activeCopy = active
            condenseHistoricalMessages(in: &activeCopy)
            applyLoadedSession(activeCopy)
        } else {
            let activeId = AIRuntimeCoordinator.shared.activeSessionId
            Task.detached(priority: .userInitiated) {
                let summaries = AIChatHistoryStore.shared.loadSessionSummaries(for: bid)
                let targetId = (activeId != nil && summaries.contains(where: { $0.id == activeId }))
                    ? activeId!
                    : summaries.first?.id

                var loadedSession: AIChatSession? = nil
                if let targetId = targetId {
                    loadedSession = AIChatHistoryStore.shared.loadSession(id: targetId, for: bid)
                }

                await MainActor.run {
                    if var session = loadedSession {
                        self.condenseHistoricalMessages(in: &session)
                        self.applyLoadedSession(session)
                    } else {
                        self.startNewChat()
                        self.isLoadingSession = false
                    }
                }
            }
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

    internal func applyLoadedSession(_ session: AIChatSession) {
        currentSession = session
        currentSessionId = session.id
        selectedMode = session.mode
        visibleMessageCount = 20

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
        isLoadingSession = false
    }

    internal func switchToSession(_ session: AIChatSession) {
        var copy = session
        condenseHistoricalMessages(in: &copy)
        applyLoadedSession(copy)
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
        visibleMessageCount = 20
        batchExtractedNames.removeAll()
        isLoadingSession = false
        AIChatHistoryStore.shared.saveSession(newSession, for: bookId)
    }

    /// Định dạng danh sách tên riêng thành văn bản thuần Name gốc=nghĩa.
    nonisolated internal func condenseExtractedNamesToText(names: [AIExtractedName], title: String? = nil) -> String {
        var lines: [String] = []
        if let header = title, !header.isEmpty {
            lines.append(header)
        }
        for item in names {
            let meaning = item.suggestedMeaning.isEmpty ? item.original : item.suggestedMeaning
            lines.append("\(item.original)=\(meaning)")
        }
        return lines.joined(separator: "\n")
    }

    /// Rút gọn các tin nhắn có danh sách tên riêng cũ trong lịch sử chat về văn bản thuần.
    internal func condenseHistoricalMessages(in session: inout AIChatSession) {
        var changed = false
        for i in session.messages.indices {
            let msg = session.messages[i]
            if msg.role == .assistant && !msg.isStreaming, let names = msg.extractedNames, !names.isEmpty {
                let plainText = condenseExtractedNamesToText(names: names, title: "Danh sách tên riêng:")
                session.messages[i].content = plainText
                session.messages[i].extractedNames = nil
                changed = true
            }
        }
        if changed {
            AIChatHistoryStore.shared.saveSession(session, for: session.bookId)
        }
    }
}
