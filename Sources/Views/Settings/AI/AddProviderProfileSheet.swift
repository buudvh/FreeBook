import SwiftUI

/// Sheet modal thêm Option Provider mới với Picker chọn mẫu thông minh và nút Load Models từ API.
public struct AddProviderProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let existingProfiles: [AIProviderProfile]
    public let onAddProfile: (AIProviderProfile) -> Void

    @State private var selectedTemplateKey: String = "gemini"
    @State private var name: String = "Google Gemini"
    @State private var baseURL: String = "https://generativelanguage.googleapis.com/v1beta/openai/"
    @State private var apiKey: String = ""
    @State private var apiFormat: String = "openai"
    @State private var modelsText: String = "gemini-2.0-flash\ngemini-2.0-flash-lite\ngemini-1.5-flash\ngemini-1.5-pro"
    @State private var isFetchingModels: Bool = false
    @State private var fetchMessage: String? = nil
    @State private var isFetchSuccess: Bool = false

    public init(
        existingProfiles: [AIProviderProfile],
        onAddProfile: @escaping (AIProviderProfile) -> Void
    ) {
        self.existingProfiles = existingProfiles
        self.onAddProfile = onAddProfile
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Mẫu Thiết Lập Nhanh")) {
                    Picker("Mẫu Provider", selection: $selectedTemplateKey) {
                        Section("Mẫu có sẵn (Built-in)") {
                            Text("Google Gemini").tag("gemini")
                            Text("OpenAI (API Key)").tag("openai")
                            Text("Anthropic Claude (Chính thức)").tag("anthropic")
                            Text("DeepSeek").tag("deepseek")
                            Text("Anthropic Claude (OpenRouter)").tag("openrouter")
                            Text("Groq Fast").tag("groq")
                            Text("Ollama Local (Offline)").tag("ollama")
                        }

                        if !existingProfiles.isEmpty {
                            Section("Nhân bản từ Profile đã lưu") {
                                ForEach(existingProfiles) { p in
                                    Text("📄 \(p.name)").tag("saved_\(p.id)")
                                }
                            }
                        }

                        Section("Tùy chỉnh") {
                            Text("Trống (Tự nhập từ đầu)").tag("custom")
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedTemplateKey) { _, newKey in
                        applyTemplate(key: newKey)
                    }
                }

                Section(header: Text("Thông Tin Kết Nối")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tên Provider mới")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("VD: OpenRouter Cá Nhân, DeepSeek V3...", text: $name)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Định dạng API")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Định dạng API", selection: $apiFormat) {
                            Text("OpenAI").tag("openai")
                            Text("Anthropic Claude").tag("anthropic")
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Base URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("https://...", text: $baseURL)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("Nhập API Key...", text: $apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section(header: Text("Quản Lý Danh Sách Model")) {
                    HStack {
                        Text("Danh sách Models:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: fetchModelsFromAPI) {
                            HStack(spacing: 4) {
                                if isFetchingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "bolt.fill")
                                }
                                Text("Load từ API")
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                        }
                        .disabled(isFetchingModels || baseURL.isEmpty)
                    }

                    if let message = fetchMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(isFetchSuccess ? .green : .red)
                    }

                    TextEditor(text: $modelsText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                Section {
                    Button(action: saveNewProfile) {
                        HStack {
                            Spacer()
                            Text("Lưu Option Provider Mới")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Thêm Option Provider Mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func applyTemplate(key: String) {
        if key.hasPrefix("saved_") {
            let savedId = String(key.dropFirst("saved_".count))
            if let p = existingProfiles.first(where: { $0.id == savedId }) {
                name = "\(p.name) (Bản sao)"
                baseURL = p.baseURL
                apiKey = p.apiKey
                apiFormat = p.apiFormat
                modelsText = p.availableModels.joined(separator: "\n")
            }
        } else {
            switch key {
            case "gemini":
                name = "Google Gemini"
                baseURL = "https://generativelanguage.googleapis.com/v1beta/openai/"
                apiFormat = "openai"
                modelsText = ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-flash", "gemini-1.5-pro"].joined(separator: "\n")
            case "openai":
                name = "OpenAI"
                baseURL = "https://api.openai.com/v1"
                apiFormat = "openai"
                modelsText = ["gpt-4o-mini", "gpt-4o", "o3-mini", "o1"].joined(separator: "\n")
            case "anthropic":
                name = "Anthropic Claude"
                baseURL = "https://api.anthropic.com/v1"
                apiFormat = "anthropic"
                modelsText = [
                    "claude-3-7-sonnet-latest",
                    "claude-3-5-sonnet-latest",
                    "claude-3-5-haiku-latest",
                    "claude-3-7-sonnet-20250219",
                    "claude-3-5-sonnet-20241022",
                    "claude-3-opus-latest"
                ].joined(separator: "\n")
            case "deepseek":
                name = "DeepSeek"
                baseURL = "https://api.deepseek.com/v1"
                apiFormat = "openai"
                modelsText = ["deepseek-chat", "deepseek-reasoner"].joined(separator: "\n")
            case "openrouter":
                name = "Anthropic Claude (OpenRouter)"
                baseURL = "https://openrouter.ai/api/v1"
                apiFormat = "openai"
                modelsText = [
                    "anthropic/claude-3.7-sonnet",
                    "anthropic/claude-3.7-sonnet:thinking",
                    "anthropic/claude-3.5-sonnet",
                    "anthropic/claude-3.5-haiku",
                    "anthropic/claude-3-opus"
                ].joined(separator: "\n")
            case "groq":
                name = "Groq Fast"
                baseURL = "https://api.groq.com/openai/v1"
                apiFormat = "openai"
                modelsText = ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"].joined(separator: "\n")
            case "ollama":
                name = "Ollama Local (Offline)"
                baseURL = "http://localhost:11434/v1"
                apiFormat = "openai"
                modelsText = ["llama3.2", "qwen2.5", "deepseek-r1"].joined(separator: "\n")
            default:
                name = ""
                baseURL = ""
                apiFormat = "openai"
                modelsText = ""
            }
        }
    }

    private func fetchModelsFromAPI() {
        isFetchingModels = true
        fetchMessage = nil
        Task {
            do {
                let fetched: [String]
                if apiFormat == "anthropic" {
                    fetched = try await AnthropicClient.shared.fetchAvailableModels(
                        baseURL: baseURL,
                        apiKey: apiKey
                    )
                } else {
                    fetched = try await OpenAIClient.shared.fetchAvailableModels(
                        baseURL: baseURL,
                        apiKey: apiKey
                    )
                }
                await MainActor.run {
                    isFetchingModels = false
                    if !fetched.isEmpty {
                        modelsText = fetched.joined(separator: "\n")
                        fetchMessage = "Đã tải về thành công \(fetched.count) models từ API!"
                        isFetchSuccess = true
                    } else {
                        fetchMessage = "API không trả về model nào."
                        isFetchSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    isFetchingModels = false
                    fetchMessage = "Lỗi load models: \(error.localizedDescription)"
                    isFetchSuccess = false
                }
            }
        }
    }

    private func saveNewProfile() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let models = modelsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let newProfile = AIProviderProfile(
            id: "custom_\(UUID().uuidString.prefix(8))",
            name: cleanName.isEmpty ? "Provider Tùy Chỉnh" : cleanName,
            baseURL: cleanURL,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedModel: models.first ?? "default-model",
            availableModels: models.isEmpty ? ["default-model"] : models,
            temperature: 0.3,
            isCustom: true,
            authType: "apiKey",
            apiFormat: apiFormat
        )

        onAddProfile(newProfile)
        dismiss()
    }
}
