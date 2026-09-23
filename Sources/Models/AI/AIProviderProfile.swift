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

    public init(
        id: String,
        name: String,
        baseURL: String,
        apiKey: String = "",
        selectedModel: String = "",
        availableModels: [String] = [],
        temperature: Double = 0.3,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.selectedModel = selectedModel.isEmpty ? (availableModels.first ?? "") : selectedModel
        self.availableModels = availableModels
        self.temperature = temperature
        self.isCustom = isCustom
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

    public static let defaultOllama = AIProviderProfile(
        id: "ollama",
        name: "Ollama Local (Offline)",
        baseURL: "http://localhost:11434/v1",
        selectedModel: "llama3.2",
        availableModels: ["llama3.2", "qwen2.5", "deepseek-r1"],
        temperature: 0.3,
        isCustom: false
    )

    public static var defaultProfiles: [AIProviderProfile] {
        [defaultGemini, defaultOpenAI, defaultDeepSeek, defaultClaudeOpenRouter, defaultGroq, defaultOllama]
    }
}
