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
    public var apiFormat: String
    public var refreshToken: String?
    public var tokenExpiresAt: Date?
    public var accountEmail: String?

    public init(
        id: String,
        name: String,
        baseURL: String,
        apiKey: String = "",
        selectedModel: String = "",
        availableModels: [String] = [],
        temperature: Double = 0.3,
        isCustom: Bool = false,
        authType: String = "apiKey",
        apiFormat: String = "openai",
        refreshToken: String? = nil,
        tokenExpiresAt: Date? = nil,
        accountEmail: String? = nil
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
        self.apiFormat = apiFormat
        self.refreshToken = refreshToken
        self.tokenExpiresAt = tokenExpiresAt
        self.accountEmail = accountEmail
    }

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, selectedModel, availableModels, temperature, isCustom, authType, apiFormat, refreshToken, tokenExpiresAt, accountEmail
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
        apiFormat = try container.decodeIfPresent(String.self, forKey: .apiFormat) ?? "openai"
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        tokenExpiresAt = try container.decodeIfPresent(Date.self, forKey: .tokenExpiresAt)
        accountEmail = try container.decodeIfPresent(String.self, forKey: .accountEmail)
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

    public static let defaultAnthropic = AIProviderProfile(
        id: "anthropic",
        name: "Anthropic Claude",
        baseURL: "https://api.anthropic.com/v1",
        selectedModel: "claude-3-7-sonnet-latest",
        availableModels: [
            "claude-3-7-sonnet-latest",
            "claude-3-5-sonnet-latest",
            "claude-3-5-haiku-latest",
            "claude-3-7-sonnet-20250219",
            "claude-3-5-sonnet-20241022",
            "claude-3-opus-latest"
        ],
        temperature: 0.3,
        isCustom: false,
        apiFormat: "anthropic"
    )

    public static let defaultClaudeOpenRouter = AIProviderProfile(
        id: "claudeOpenRouter",
        name: "Anthropic Claude (OpenRouter)",
        baseURL: "https://openrouter.ai/api/v1",
        selectedModel: "anthropic/claude-3.7-sonnet",
        availableModels: [
            "anthropic/claude-3.7-sonnet",
            "anthropic/claude-3.7-sonnet:thinking",
            "anthropic/claude-3.5-sonnet",
            "anthropic/claude-3.5-haiku",
            "anthropic/claude-3-opus"
        ],
        temperature: 0.3,
        isCustom: false,
        apiFormat: "openai"
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
        [defaultGemini, defaultOpenAI, defaultAnthropic, defaultDeepSeek, defaultClaudeOpenRouter, defaultGroq, defaultOllama]
    }

    /// Mặc định không lưu sẵn profile rỗng nào, chỉ lưu khi người dùng chủ động thêm.
    public static var defaultProfiles: [AIProviderProfile] {
        []
    }
}
