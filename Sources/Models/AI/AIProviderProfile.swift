import Foundation

/// Đại diện cho cấu hình độc lập của một Provider AI.
public struct AIProviderProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var apiKey: String
    public var selectedModel: String
    public var availableModels: [String]
    public var temperature: Double
    public var isCustom: Bool
    public var authType: String

    public init(
        id: String,
        name: String,
        baseURL: String,
        apiKey: String = "",
        selectedModel: String = "",
        availableModels: [String] = [],
        temperature: Double = 0.3,
        isCustom: Bool = false,
        authType: String = "apiKey"
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.selectedModel = selectedModel.isEmpty ? (availableModels.first ?? "") : selectedModel
        self.availableModels = availableModels
        self.temperature = temperature
        self.isCustom = isCustom
        self.authType = authType
    }

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, selectedModel, availableModels, temperature, isCustom, authType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        selectedModel = try container.decode(String.self, forKey: .selectedModel)
        availableModels = try container.decode([String].self, forKey: .availableModels)
        temperature = try container.decode(Double.self, forKey: .temperature)
        isCustom = try container.decode(Bool.self, forKey: .isCustom)
        authType = try container.decodeIfPresent(String.self, forKey: .authType) ?? "apiKey"
    }

    public static let defaultGemini = AIProviderProfile(
        id: "gemini",
        name: "Google Gemini",
        baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/",
        selectedModel: "gemini-2.0-flash",
        availableModels: ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-flash", "gemini-1.5-pro"],
        temperature: 0.3,
        isCustom: false
    )

    public static let defaultOpenAI = AIProviderProfile(
        id: "openai",
        name: "OpenAI",
        baseURL: "https://api.openai.com/v1",
        selectedModel: "gpt-4o-mini",
        availableModels: ["gpt-4o-mini", "gpt-4o", "o3-mini", "o1"],
        temperature: 0.3,
        isCustom: false
    )

    public static let defaultDeepSeek = AIProviderProfile(
        id: "deepseek",
        name: "DeepSeek",
        baseURL: "https://api.deepseek.com/v1",
        selectedModel: "deepseek-chat",
        availableModels: ["deepseek-chat", "deepseek-reasoner"],
        temperature: 0.3,
        isCustom: false
    )

    public static let defaultClaudeOpenRouter = AIProviderProfile(
        id: "claudeOpenRouter",
        name: "Anthropic Claude (OpenRouter)",
        baseURL: "https://openrouter.ai/api/v1",
        selectedModel: "anthropic/claude-3.5-sonnet",
        availableModels: ["anthropic/claude-3.5-sonnet", "anthropic/claude-3.5-haiku", "anthropic/claude-3-opus"],
        temperature: 0.3,
        isCustom: false
    )

    public static let defaultGroq = AIProviderProfile(
        id: "groq",
        name: "Groq Fast",
        baseURL: "https://api.groq.com/openai/v1",
        selectedModel: "llama-3.3-70b-versatile",
        availableModels: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"],
        temperature: 0.3,
        isCustom: false
    )

    public static let defaultChatGPTWeb = AIProviderProfile(
        id: "chatgpt_web",
        name: "ChatGPT Web",
        baseURL: "https://chatgpt.com",
        selectedModel: "auto",
        availableModels: ["auto", "gpt-4o", "gpt-4o-mini", "o3-mini"],
        temperature: 0.3,
        isCustom: false,
        authType: "web"
    )

    public static let defaultOllama = AIProviderProfile(
        id: "ollama",
        name: "Ollama Local (Offline)",
        baseURL: "http://localhost:11434/v1",
        selectedModel: "llama3.2",
        availableModels: ["llama3.2", "qwen2.5", "deepseek-r1"],
        temperature: 0.3,
        isCustom: false
    )

    /// Các mẫu provider chuẩn định nghĩa sẵn để người dùng chọn khi thêm mới.
    public static var standardTemplates: [AIProviderProfile] {
        [defaultGemini, defaultOpenAI, defaultChatGPTWeb, defaultDeepSeek, defaultClaudeOpenRouter, defaultGroq, defaultOllama]
    }

    /// Mặc định không lưu sẵn profile rỗng nào, chỉ lưu khi người dùng chủ động thêm.
    public static var defaultProfiles: [AIProviderProfile] {
        []
    }
}
