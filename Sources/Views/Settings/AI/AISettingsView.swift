import SwiftUI

/// Màn hình Cài đặt API AI & Quản lý danh sách Provider Profiles.
public struct AISettingsView: View {
    @Environment(\.dismiss) internal var dismiss

    @State internal var config: AIConfiguration = AISettingsStore.shared.loadConfiguration()
    @State internal var modelsText: String = ""
    @State internal var isTestingConnection = false
    @State internal var testResultMessage: String? = nil
    @State internal var isTestSuccess = false
    @State internal var isFetchingModels = false
    @State internal var showingAddProviderSheet = false
    @State internal var showingChatGPTWebLoginSheet = false

    public init() {}

    public var body: some View {
        Form {
            // SECTION 1: DANH SÁCH CÁC PROFILE ĐÃ LƯU
            Section(header: Text("Danh Sách Profile Đã Lưu (\(config.profiles.count))")) {
                if config.profiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Chưa có cấu hình AI nào.")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Text("Bấm nút dấu cộng (+) ở góc trên bên phải để thêm cấu hình AI (Gemini, OpenAI, DeepSeek, Claude...).")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: { showingAddProviderSheet = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Thêm Cấu Hình Mới")
                            }
                            .font(.footnote.bold())
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(config.profiles) { profile in
                        Button(action: { selectProfile(profile.id) }) {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(profile.name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)

                                        if profile.isCustom {
                                            Text("Tự thêm")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.15))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)
                                        }

                                        if profile.id == config.activeProfileId {
                                            Text("Đang chọn")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.purple.opacity(0.2))
                                                .foregroundColor(.purple)
                                                .cornerRadius(4)
                                        }
                                    }

                                    Text("\(profile.baseURL) • \(profile.selectedModel.isEmpty ? "Chưa có model" : profile.selectedModel)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if profile.id == config.activeProfileId {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.purple)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

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

                    if config.activeProfile.authType == "web" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Xác thực ChatGPT Web")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button(action: { showingChatGPTWebLoginSheet = true }) {
                                HStack {
                                    Image(systemName: "safari.fill")
                                        .foregroundColor(.green)
                                    Text("Đăng nhập / Quản lý ChatGPT Web")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Text("Đăng nhập trên chatgpt.com để dùng hạn ngạch web miễn phí / Plus không giới hạn.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Nhập API Key...", text: Binding(
                                get: { config.activeProfile.apiKey },
                                set: { newKey in
                                    var p = config.activeProfile
                                    p.apiKey = newKey
                                    config.updateActiveProfile(p)
                                }
                            ))
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
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
                            Text("Danh sách Model (mỗi dòng 1 model):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(parsedModelsCount) models")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        TextEditor(text: $modelsText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 100)
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
                saveConfigSilently()
            }
        }
        .sheet(isPresented: $showingChatGPTWebLoginSheet) {
            ChatGPTWebLoginSheet()
        }
        .onAppear {
            config = AISettingsStore.shared.loadConfiguration()
            modelsText = config.activeProfile.availableModels.joined(separator: "\n")
        }
        .onChange(of: config) { _, newConfig in
            AISettingsStore.shared.saveConfiguration(newConfig)
        }
        .onChange(of: modelsText) { _, newText in
            syncModelsFromText(newText)
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
            }
        }
    }

    internal var parsedModelsCount: Int {
        modelsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }
}
