import SwiftUI

/// Màn hình Cài đặt API AI & Quản lý danh sách Model.
public struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var config: AIConfiguration = AISettingsStore.shared.loadConfiguration()
    @State private var modelsText: String = ""
    @State private var isTestingConnection = false
    @State private var testResultMessage: String? = nil
    @State private var isTestSuccess = false
    @State private var isFetchingModels = false

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Nhà Cung Cấp & Endpoint")) {
                Picker("Preset nhà cung cấp", selection: $config.preset) {
                    ForEach(AIProviderPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: config.preset) { _, newPreset in
                    applyPreset(newPreset)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("API Base URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("https://api.openai.com/v1", text: $config.baseURL)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("Nhập API Key...", text: $config.apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            Section(header: Text("Quản Lý Danh Sách Model")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Model đang chọn:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(config.selectedModel.isEmpty ? "Chưa chọn" : config.selectedModel)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
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
                    .disabled(isFetchingModels || config.baseURL.isEmpty)
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
                        .frame(minHeight: 110)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            Section(header: Text("Tham Số AI")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature (Độ sáng tạo)")
                        Spacer()
                        Text(String(format: "%.1f", config.temperature))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $config.temperature, in: 0.0...1.0, step: 0.1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("System Prompt mặc định")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $config.systemPrompt)
                        .font(.caption)
                        .frame(minHeight: 80)
                }
            }

            Section {
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
                .disabled(isTestingConnection || config.baseURL.isEmpty)

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
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") {
                    saveAndDismiss()
                }
            }
        }
        .onAppear {
            modelsText = config.availableModels.joined(separator: "\n")
        }
    }

    private var parsedModelsCount: Int {
        modelsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private func applyPreset(_ preset: AIProviderPreset) {
        if preset != .custom {
            config.baseURL = preset.defaultBaseURL
            config.availableModels = preset.defaultModels
            config.selectedModel = preset.defaultModels.first ?? ""
            modelsText = preset.defaultModels.joined(separator: "\n")
        }
    }

    private func fetchModelsFromAPI() {
        isFetchingModels = true
        testResultMessage = nil
        Task {
            do {
                let fetched = try await OpenAIClient.shared.fetchAvailableModels(
                    baseURL: config.baseURL,
                    apiKey: config.apiKey
                )
                await MainActor.run {
                    isFetchingModels = false
                    if !fetched.isEmpty {
                        config.availableModels = fetched
                        modelsText = fetched.joined(separator: "\n")
                        if !fetched.contains(config.selectedModel) {
                            config.selectedModel = fetched.first ?? config.selectedModel
                        }
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
                    baseURL: config.baseURL,
                    apiKey: config.apiKey
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
        let lines = modelsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !lines.isEmpty {
            config.availableModels = lines
            if !lines.contains(config.selectedModel) {
                config.selectedModel = lines.first ?? config.selectedModel
            }
        }
        AISettingsStore.shared.saveConfiguration(config)
        dismiss()
    }
}
