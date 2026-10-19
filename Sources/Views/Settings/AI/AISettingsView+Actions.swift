import SwiftUI

/// Các hàm xử lý hành vi và kết nối mạng của AISettingsView.
extension AISettingsView {
    internal func selectProfile(_ id: String) {
        config.activeProfileId = id
        modelsText = config.activeProfile.availableModels.joined(separator: "\n")
        apiKeysText = config.activeProfile.allEffectiveApiKeys().joined(separator: "\n")
        testResultMessage = nil
        saveConfigSilently()
    }

    internal func deleteCurrentProfile() {
        let idToDelete = config.activeProfileId
        config.deleteProfile(id: idToDelete)
        modelsText = config.activeProfile.availableModels.joined(separator: "\n")
        apiKeysText = config.activeProfile.allEffectiveApiKeys().joined(separator: "\n")
        testResultMessage = nil
        saveConfigSilently()
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
}
