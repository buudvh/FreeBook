import SwiftUI

/// Màn hình Cài đặt API AI & Quản lý danh sách Provider Profiles.
public struct AISettingsView: View {
    @Environment(\.dismiss) internal var dismiss

    @State internal var config: AIConfiguration = AISettingsStore.shared.loadConfiguration()
    @State internal var modelsText: String = ""
    @State internal var apiKeysText: String = ""
    @State internal var isTestingConnection = false
    @State internal var testResultMessage: String? = nil
    @State internal var isTestSuccess = false
    @State internal var isFetchingModels = false
    @State internal var showingAddProviderSheet = false
    @State private var showingClearAllSessionsAlert = false

    public init() {}

    public var body: some View {
        Form {
            // SECTION 1: DANH SÁCH CÁC PROFILE ĐÃ LƯU
            AISettingsProfileSectionView(
                profiles: config.profiles,
                activeProfileId: config.activeProfileId,
                onSelectProfile: { selectProfile($0) },
                onAddProfile: { showingAddProviderSheet = true }
            )

            // SECTION 2: TÙY CHỈNH PROMPT
            Section(header: Text("Tùy Chỉnh Prompt")) {
                NavigationLink {
                    AIPromptSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "text.bubble.fill")
                            .foregroundColor(.purple)
                        Text("Tùy chỉnh Prompt AI & Trích xuất")
                            .font(.subheadline)
                    }
                }
            }

            // SECTION 3: CHI TIẾT PROFILE ĐANG CHỌN (NẾU CÓ PROFILE)
            if !config.profiles.isEmpty {
                Section(header: Text("Chi Tiết Profile: \(config.activeProfile.name)")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tên Provider Profile")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Tên Provider...", text: Binding(
                            get: { config.activeProfile.name },
                            set: { newName in
                                var p = config.activeProfile
                                p.name = newName
                                config.updateActiveProfile(p)
                            }
                        ))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Định dạng API")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Định dạng API", selection: Binding(
                            get: { config.activeProfile.apiFormat },
                            set: { newFormat in
                                var p = config.activeProfile
                                p.apiFormat = newFormat
                                config.updateActiveProfile(p)
                            }
                        )) {
                            Text("OpenAI").tag("openai")
                            Text("Anthropic Claude").tag("anthropic")
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Base URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("https://...", text: Binding(
                            get: { config.activeProfile.baseURL },
                            set: { newURL in
                                var p = config.activeProfile
                                p.baseURL = newURL
                                config.updateActiveProfile(p)
                            }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    }

                    // Quản lý API Keys
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("API Keys (\(parsedKeysCount) keys):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            clipboardToolbar(for: $apiKeysText) {
                                syncApiKeysFromText(apiKeysText)
                            }
                        }
                        TextEditor(text: $apiKeysText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: apiKeysText) { _, newText in
                                syncApiKeysFromText(newText)
                            }
                        Text("Mỗi dòng 1 key. Tự động chuyển key tiếp theo khi gặp lỗi quota hoặc 401/403/429.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    if config.activeProfile.apiFormat == "anthropic" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Định dạng Header Auth (Anthropic)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Header Auth", selection: Binding(
                                get: { config.activeProfile.anthropicAuthHeader },
                                set: { newHeader in
                                    var p = config.activeProfile
                                    p.anthropicAuthHeader = newHeader
                                    config.updateActiveProfile(p)
                                }
                            )) {
                                Text("Authorization: Bearer <token>").tag("bearer")
                                Text("x-api-key").tag("x-api-key")
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Quản lý model của profile
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Model đang chọn:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(config.activeProfile.selectedModel.isEmpty ? "Chưa chọn" : config.activeProfile.selectedModel)
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                        }
                        Spacer()
                        Button(action: fetchModelsFromAPI) {
                            HStack(spacing: 4) {
                                if isFetchingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text("Load từ API")
                            }
                            .font(.subheadline)
                        }
                        .disabled(isFetchingModels || config.activeProfile.baseURL.isEmpty)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Danh sách Model (\(parsedModelsCount) models):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            clipboardToolbar(for: $modelsText) {
                                syncModelsFromText(modelsText)
                            }
                        }
                        TextEditor(text: $modelsText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .onChange(of: modelsText) { _, newText in
                                syncModelsFromText(newText)
                            }
                    }

                    Button(role: .destructive, action: deleteCurrentProfile) {
                        HStack {
                            Spacer()
                            Image(systemName: "trash")
                            Text("Xoá Profile Này")
                            Spacer()
                        }
                    }
                }

                // SECTION 4: THAM SỐ VÀ TEST KẾT NỐI
                Section(header: Text("Tham Số AI & Kiểm Tra")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Temperature (Độ sáng tạo)")
                            Spacer()
                            Text(String(format: "%.1f", config.activeProfile.temperature))
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { config.activeProfile.temperature },
                                set: { newTemp in
                                    var p = config.activeProfile
                                    p.temperature = newTemp
                                    config.updateActiveProfile(p)
                                }
                            ),
                            in: 0.0...1.0,
                            step: 0.1
                        )
                    }

                    Button(action: testConnection) {
                        HStack {
                            Spacer()
                            if isTestingConnection {
                                ProgressView()
                                    .padding(.trailing, 6)
                            } else {
                                Image(systemName: "bolt.horizontal.fill")
                                    .padding(.trailing, 2)
                            }
                            Text("Kiểm tra kết nối API")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .disabled(isTestingConnection || config.activeProfile.baseURL.isEmpty)

                    if let message = testResultMessage {
                        HStack(spacing: 8) {
                            Image(systemName: isTestSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isTestSuccess ? .green : .red)
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(isTestSuccess ? .green : .red)
                        }
                    }
                }
            }

            // SECTION 5: LỊCH SỬ CHAT AI
            Section(header: Text("Lịch Sử Chat AI")) {
                NavigationLink {
                    AIChatAllSessionsManagerView()
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundColor(.blue)
                        Text("Quản lý danh sách phiên chat")
                            .font(.subheadline)
                    }
                }

                Button(role: .destructive) {
                    showingClearAllSessionsAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Dọn dẹp tất cả phiên chat")
                    }
                }
            }
        }
        .navigationTitle("Cấu hình AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddProviderSheet = true }) {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingAddProviderSheet) {
            AddProviderProfileSheet(existingProfiles: config.profiles) { newProfile in
                config.updateActiveProfile(newProfile)
                config.activeProfileId = newProfile.id
                modelsText = newProfile.availableModels.joined(separator: "\n")
                apiKeysText = newProfile.allEffectiveApiKeys().joined(separator: "\n")
                saveConfigSilently()
            }
        }
        .alert("Dọn dẹp tất cả phiên chat?", isPresented: $showingClearAllSessionsAlert) {
            Button("Dọn dẹp tất cả", role: .destructive) {
                AIChatHistoryStore.shared.clearAllSessionsAcrossAllBooks()
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Hành động này sẽ xóa vĩnh viễn toàn bộ lịch sử trò chuyện AI của tất cả truyện và không thể hoàn tác.")
        }
        .onAppear {
            config = AISettingsStore.shared.loadConfiguration()
            modelsText = config.activeProfile.availableModels.joined(separator: "\n")
            apiKeysText = config.activeProfile.allEffectiveApiKeys().joined(separator: "\n")
        }
        .onChange(of: config) { _, newConfig in
            AISettingsStore.shared.saveConfiguration(newConfig)
        }
        .onChange(of: modelsText) { _, newText in
            syncModelsFromText(newText)
            AISettingsStore.shared.saveConfiguration(config)
        }
        .onChange(of: apiKeysText) { _, newText in
            syncApiKeysFromText(newText)
            AISettingsStore.shared.saveConfiguration(config)
        }
        .onDisappear {
            saveConfigSilently()
        }
        .onReceive(NotificationCenter.default.publisher(for: AISettingsStore.didChangeNotification)) { _ in
            let latest = AISettingsStore.shared.loadConfiguration()
            if latest != config {
                config = latest
                modelsText = config.activeProfile.availableModels.joined(separator: "\n")
                apiKeysText = config.activeProfile.allEffectiveApiKeys().joined(separator: "\n")
            }
        }
    }

    internal var parsedKeysCount: Int {
        apiKeysText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    internal var parsedModelsCount: Int {
        modelsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }
}
