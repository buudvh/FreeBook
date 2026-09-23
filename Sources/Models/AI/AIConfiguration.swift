import Foundation

/// Cấu hình kết nối tới OpenAI-compatible API.
public struct AIConfiguration: Codable, Sendable, Equatable {
    public var preset: AIProviderPreset
    public var baseURL: String
    public var apiKey: String
    public var selectedModel: String
    public var availableModels: [String]
    public var temperature: Double
    public var systemPrompt: String

    public init(
        preset: AIProviderPreset = .gemini,
        baseURL: String = AIProviderPreset.gemini.defaultBaseURL,
        apiKey: String = "",
        selectedModel: String = "gemini-2.0-flash",
        availableModels: [String] = AIProviderPreset.gemini.defaultModels,
        temperature: Double = 0.3,
        systemPrompt: String = AIConfiguration.defaultSystemPrompt
    ) {
        self.preset = preset
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.selectedModel = selectedModel
        self.availableModels = availableModels
        self.temperature = temperature
        self.systemPrompt = systemPrompt
    }

    public static let defaultSystemPrompt: String = """
    Bạn là AI Trợ Lý đọc truyện chuyên nghiệp tích hợp trong app FreeBook (FreeBook AI Harness).
    Nhiệm vụ của bạn là:
    - Trả lời, tóm tắt, giải thích bối cảnh, phân tích nhân vật và tình tiết truyện một cách chính xác, hấp dẫn.
    - Trích xuất tên riêng (Nhân vật, Địa danh, Tông môn, Công pháp...) từ văn bản raw tiếng Trung chưa dịch.
    - Tuân thủ chế độ quyền hạn của người dùng (Ask, Plan, Bypass) khi gọi các công cụ sửa đổi dữ liệu truyện.
    """

    public static var `default`: AIConfiguration {
        AIConfiguration()
    }
}
