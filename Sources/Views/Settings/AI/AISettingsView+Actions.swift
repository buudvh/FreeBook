import SwiftUI

/// Các hàm xử lý hành vi và kết nối mạng của AISettingsView.
extension AISettingsView {
    internal func selectProfile(_ id: String) {
        config.activeProfileId = id
        modelsText = config.activeProfile.availableModels.joined(separator: "\n")
        apiKeysText = config.activeProfile.allEffectiveApiKeys().joined(separator: "\n")
        testResultMessage = nil
        saveConfigSilently()
        refreshGoogleAccountCount()
    }

    /// Đếm tài khoản Google của provider Chế độ AI đang dùng (hoặc provider Chế độ AI đầu tiên) — 1.3.616.
    internal func refreshGoogleAccountCount() {
        let profile = config.activeProfile.isGoogleAIMode
            ? config.activeProfile
            : config.profiles.first(where: { $0.isGoogleAIMode })
        googleAccountCount = profile.map { GoogleAccountStore.accounts(forProfileId: $0.id).count } ?? 0
    }

    internal func deleteCurrentProfile() {
        let idToDelete = config.activeProfileId
        config.deleteProfile(id: idToDelete)
        // Xoá profile Chế độ AI thì xoá luôn các tài khoản Google của nó (1.3.616) — không để lại tài khoản mồ côi.
        GoogleAccountStore.deleteAll(profileId: idToDelete)
        modelsText = config.activeProfile.availableModels.joined(separator: "\n")
        apiKeysText = config.activeProfile.allEffectiveApiKeys().joined(separator: "\n")
        testResultMessage = nil
        saveConfigSilently()
        refreshGoogleAccountCount()
    }

    internal func syncModelsFromText(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var p = config.activeProfile
        p.availableModels = lines
        if !lines.isEmpty && !lines.contains(p.selectedModel) {
            p.selectedModel = lines.first ?? ""
        }
        config.updateActiveProfile(p)
    }

    internal func syncApiKeysFromText(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var p = config.activeProfile
        p.apiKeys = lines
        p.apiKey = lines.first ?? ""
        config.updateActiveProfile(p)
    }

    internal func saveConfigSilently() {
        syncModelsFromText(modelsText)
        syncApiKeysFromText(apiKeysText)
        AISettingsStore.shared.saveConfiguration(config)
    }

    internal func fetchModelsFromAPI() {
        // Chế độ AI của Google không có danh sách model (khối model đã ẩn) — không rơi sang nhánh OpenAI.
        guard !config.activeProfile.isGoogleAIMode else { return }
        isFetchingModels = true
        testResultMessage = nil
        saveConfigSilently()
        let currentProfile = config.activeProfile
        Task {
            do {
                let fetched: [String]
                if currentProfile.isGeminiWeb {
                    fetched = try await GeminiWebClient.shared.fetchAvailableModels()
                } else if currentProfile.apiFormat == "anthropic" {
                    fetched = try await AnthropicClient.shared.fetchAvailableModels(
                        baseURL: currentProfile.baseURL,
                        apiKey: currentProfile.apiKey,
                        apiKeys: currentProfile.allEffectiveApiKeys(),
                        authHeader: currentProfile.anthropicAuthHeader
                    )
                } else {
                    fetched = try await OpenAIClient.shared.fetchAvailableModels(
                        baseURL: currentProfile.baseURL,
                        apiKey: currentProfile.apiKey,
                        apiKeys: currentProfile.allEffectiveApiKeys()
                    )
                }
                await MainActor.run {
                    isFetchingModels = false
                    if !fetched.isEmpty {
                        var p = config.activeProfile
                        p.availableModels = fetched
                        if !fetched.contains(p.selectedModel) {
                            p.selectedModel = fetched.first ?? p.selectedModel
                        }
                        config.updateActiveProfile(p)
                        modelsText = fetched.joined(separator: "\n")
                        testResultMessage = "Đã tải thành công \(fetched.count) models từ API!"
                        isTestSuccess = true
                    } else {
                        testResultMessage = "API không trả về model nào."
                        isTestSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    isFetchingModels = false
                    testResultMessage = "Lỗi load models: \(error.localizedDescription)"
                    isTestSuccess = false
                }
            }
        }
    }

    internal func testConnection() {
        isTestingConnection = true
        testResultMessage = nil
        saveConfigSilently()
        let currentConfig = config
        Task {
            do {
                let responseText: String
                if currentConfig.activeProfile.isGeminiWeb {
                    responseText = try await GeminiWebClient.shared.testChatPing(config: currentConfig)
                } else if currentConfig.activeProfile.isGoogleAIMode {
                    responseText = try await GoogleAIModeClient.shared.testChatPing(config: currentConfig)
                } else if currentConfig.activeProfile.apiFormat == "anthropic" {
                    responseText = try await AnthropicClient.shared.testChatPing(config: currentConfig)
                } else {
                    responseText = try await OpenAIClient.shared.testChatPing(config: currentConfig)
                }
                await MainActor.run {
                    isTestingConnection = false
                    isTestSuccess = true
                    let preview = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    testResultMessage = "Kết nối thành công! Phản hồi: \(preview.prefix(60))"
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    isTestSuccess = false
                    testResultMessage = "Kết nối thất bại: \(error.localizedDescription)"
                }
            }
        }
    }

    @ViewBuilder
    internal func clipboardToolbar(for text: Binding<String>, onPaste: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Button {
                text.wrappedValue = ""
                onPaste?()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(width: 28, height: 26)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)

            Button {
                UIPasteboard.general.string = text.wrappedValue
            } label: {
                AppGlyph.copy.image(size: 13)
                    .frame(width: 28, height: 26)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .disabled(text.wrappedValue.isEmpty)

            Button {
                appendClipboard(to: text)
                onPaste?()
            } label: {
                AppGlyph.paste.image(size: 13)
                    .frame(width: 28, height: 26)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
        }
    }

    internal func appendClipboard(to text: Binding<String>) {
        guard let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty else {
            return
        }
        let current = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            text.wrappedValue = clip
        } else {
            text.wrappedValue = current + "\n" + clip
        }
    }
}
