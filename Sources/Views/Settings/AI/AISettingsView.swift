import SwiftUI

/// Màn hình Cài đặt API AI & Quản lý danh sách Provider Profiles.
public struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var config: AIConfiguration = AISettingsStore.shared.loadConfiguration()
    @State private var modelsText: String = ""
    @State private var isTestingConnection = false
    @State private var testResultMessage: String? = nil
    @State private var isTestSuccess = false
    @State private var isFetchingModels = false
    @State private var showingAddProviderSheet = false

    public init() {}

    public var body: some View {
        Form {
            // SECTION 1: DANH SÁCH CÁC PROFILE ĐÃ LƯU
            Section(header: Text("Danh Sách Profile Đã Lưu (\(config.profiles.count))")) {
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

            // SECTION 2: CHI TIẾT PROFILE ĐANG CHỌN
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

                // Xoá Profile (chỉ dành cho profile tự thêm)
                if config.activeProfile.isCustom {
                    Button(role: .destructive, action: deleteCurrentProfile) {
                        HStack {
                            Spacer()
                            Image(systemName: "trash")
                            Text("Xoá Profile Này")
                            Spacer()
                        }
                    }
                }
            }

            // SECTION 3: THAM SỐ VÀ TEST KẾT NỐI
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("System Prompt mặc định")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $config.systemPrompt)
                        .font(.caption)
                        .frame(minHeight: 70)
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
        .navigationTitle("Cấu hình AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    // DUY NHẤT 1 NÚT ICON + TRÊN NAV BAR ĐỂ THÊM PROFILE MỚI
                    Button(action: { showingAddProviderSheet = true }) {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }

                    Button("Lưu") {
                        saveAndDismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .sheet(isPresented: $showingAddProviderSheet) {
            AddProviderProfileSheet(existingProfiles: config.profiles) { newProfile in
                config.updateActiveProfile(newProfile)
                config.activeProfileId = newProfile.id
                modelsText = newProfile.availableModels.joined(separator: "\n")
            }
        }
        .onAppear {
            modelsText = config.activeProfile.availableModels.joined(separator: "\n")
        }
    }

    private var parsedModelsCount: Int {
        modelsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private func selectProfile(_ id: String) {
        config.activeProfileId = id
        modelsText = config.activeProfile.availableModels.joined(separator: "\n")
        testResultMessage = nil
    }

    private func deleteCurrentProfile() {
        let idToDelete = config.activeProfileId
        config.deleteProfile(id: idToDelete)
        modelsText = config.activeProfile.availableModels.joined(separator: "\n")
        testResultMessage = nil
    }

    private func syncModelsFromText(_ text: String) {
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

    private func fetchModelsFromAPI() {
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

    private func testConnection() {
        isTestingConnection = true
        testResultMessage = nil
        Task {
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

    private func saveAndDismiss() {
        syncModelsFromText(modelsText)
        AISettingsStore.shared.saveConfiguration(config)
        dismiss()
    }
}
