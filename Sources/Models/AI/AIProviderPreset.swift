import Foundation

/// Các mẫu cài đặt nhà cung cấp API AI phổ biến.
public enum AIProviderPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case gemini = "gemini"
    case openai = "openai"
    case chatgptOAuth = "chatgpt_oauth"
    case chatgptWeb = "chatgpt_web"
    case claudeOpenRouter = "claudeOpenRouter"
    case deepseek = "deepseek"
    case groq = "groq"
    case ollama = "ollama"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openai: return "OpenAI"
        case .chatgptOAuth: return "ChatGPT (OAuth - Đăng nhập tài khoản)"
        case .chatgptWeb: return "ChatGPT Web (Không giới hạn Quota)"
        case .claudeOpenRouter: return "Anthropic Claude (qua OpenRouter)"
        case .deepseek: return "DeepSeek"
        case .groq: return "Groq"
        case .ollama: return "Ollama Local (Offline)"
        case .custom: return "Tùy chỉnh (Custom Endpoint)"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/"
        case .openai: return "https://api.openai.com/v1"
        case .chatgptOAuth: return "https://api.openai.com/v1"
        case .chatgptWeb: return "https://chatgpt.com"
        case .claudeOpenRouter: return "https://openrouter.ai/api/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .custom: return ""
        }
    }

    public var defaultModels: [String] {
        switch self {
        case .gemini:
            return ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-flash", "gemini-1.5-pro"]
        case .openai:
            return ["gpt-4o-mini", "gpt-4o", "o3-mini", "o1"]
        case .chatgptOAuth:
            return ["gpt-4o", "gpt-4o-mini", "o3-mini", "o1"]
        case .chatgptWeb:
            return ["auto", "gpt-4o", "gpt-4o-mini", "o3-mini"]
        case .claudeOpenRouter:
            return ["anthropic/claude-3.5-sonnet", "anthropic/claude-3.5-haiku", "anthropic/claude-3-opus"]
        case .deepseek:
            return ["deepseek-chat", "deepseek-reasoner"]
        case .groq:
            return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"]
        case .ollama:
            return ["llama3.2", "qwen2.5", "deepseek-r1"]
        case .custom:
            return ["default-model"]
        }
    }
}
