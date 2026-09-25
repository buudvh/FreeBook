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

        if config.activeProfile.authType == "oauth" {
            guard config.activeProfile.isOAuthLoggedIn else {
                testResultMessage = "Chưa đăng nhập OpenAI OAuth. Hãy bấm Đăng nhập ở trên."
                isTestSuccess = false
                return
            }
            isFetchingModels = true
            testResultMessage = nil
            Task {
                do {
                    let token = try await OpenAIOAuthManager.shared.getValidAccessToken(for: config.activeProfile)
                    let fetched = try await OpenAIClient.shared.fetchAvailableModels(
                        baseURL: config.activeProfile.baseURL,
                        apiKey: token
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
                            testResultMessage = "Đã tải thành công \(fetched.count) models từ OpenAI!"
                            isTestSuccess = true
                        } else {
                            testResultMessage = "Không tìm thấy model nào từ tài khoản."
                            isTestSuccess = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        isFetchingModels = false
                        testResultMessage = "Lỗi tải models OAuth: \(error.localizedDescription)"
                        isTestSuccess = false
                    }
                }
            }
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

            if config.activeProfile.authType == "oauth" {
                guard config.activeProfile.isOAuthLoggedIn else {
                    await MainActor.run {
                        isTestingConnection = false
                        isTestSuccess = false
                        testResultMessage = "Chưa đăng nhập OpenAI OAuth. Hãy bấm Đăng nhập ở trên."
                    }
                    return
                }
                do {
                    let token = try await OpenAIOAuthManager.shared.getValidAccessToken(for: config.activeProfile)
                    let models = try await OpenAIClient.shared.fetchAvailableModels(
                        baseURL: config.activeProfile.baseURL,
                        apiKey: token
                    )
                    await MainActor.run {
                        isTestingConnection = false
                        isTestSuccess = true
                        testResultMessage = "Kết nối OAuth thành công! Xác thực tài khoản hợp lệ (\(models.count) models)."
                    }
                } catch {
                    await MainActor.run {
                        isTestingConnection = false
                        isTestSuccess = false
                        testResultMessage = "Xác thực OAuth thất bại: \(error.localizedDescription)"
                    }
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
