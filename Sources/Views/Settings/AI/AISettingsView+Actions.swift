import SwiftUI

/// Các hàm xử lý hành vi và kết nối mạng của AISettingsView.
extension AISettingsView {
    internal func selectProfile(_ id: String) {
        config.activeProfileId = id
        modelsText = config.activeProfile.availableModels.joined(separator: "\n")
        testResultMessage = nil
        saveConfigSilently()
    }

    internal func deleteCurrentProfile() {
        let idToDelete = config.activeProfileId
        config.deleteProfile(id: idToDelete)
        modelsText = config.activeProfile.availableModels.joined(separator: "\n")
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

    internal func saveConfigSilently() {
        syncModelsFromText(modelsText)
        AISettingsStore.shared.saveConfiguration(config)
    }

    internal func fetchModelsFromAPI() {
        if config.activeProfile.authType == "web" {
            testResultMessage = "ChatGPT Web hỗ trợ các model: auto, gpt-4o, gpt-4o-mini, o3-mini."
            isTestSuccess = true
            return
        }

        isFetchingModels = true
        testResultMessage = nil
        Task {
            do {
                let fetched = try await OpenAIClient.shared.fetchAvailableModels(
                    baseURL: config.activeProfile.baseURL,
                    apiKey: config.activeProfile.apiKey
                )
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
        Task {
            if config.activeProfile.authType == "web" {
                let loggedIn = await ChatGPTWebClient.shared.checkLoginStatus()
                await MainActor.run {
                    isTestingConnection = false
                    isTestSuccess = loggedIn
                    testResultMessage = loggedIn ? "Đã kết nối thành công với phiên ChatGPT Web!" : "Chưa đăng nhập ChatGPT Web. Hãy bấm Đăng nhập ở trên."
                }
                return
            }

            do {
                let models = try await OpenAIClient.shared.fetchAvailableModels(
                    baseURL: config.activeProfile.baseURL,
                    apiKey: config.activeProfile.apiKey
                )
                await MainActor.run {
                    isTestingConnection = false
                    isTestSuccess = true
                    testResultMessage = "Kết nối thành công! Tìm thấy \(models.count) models."
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
