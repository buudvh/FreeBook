import Foundation

/// Cấu hình kết nối tới OpenAI-compatible API với quản lý đa Profile.
public struct AIConfiguration: Codable, Sendable, Equatable {
    public var profiles: [AIProviderProfile]
    public var activeProfileId: String
    public var systemPrompt: String

    public init(
        profiles: [AIProviderProfile] = AIProviderProfile.defaultProfiles,
        activeProfileId: String = "gemini",
        systemPrompt: String = AIConfiguration.defaultSystemPrompt
    ) {
        self.profiles = profiles.isEmpty ? AIProviderProfile.defaultProfiles : profiles
        self.activeProfileId = activeProfileId
        self.systemPrompt = systemPrompt
    }

    public var activeProfile: AIProviderProfile {
        get {
            profiles.first(where: { $0.id == activeProfileId }) ?? profiles.first ?? .defaultGemini
        }
        set {
            if let idx = profiles.firstIndex(where: { $0.id == newValue.id }) {
                profiles[idx] = newValue
            } else {
                profiles.append(newValue)
            }
        }
    }

    public mutating func updateActiveProfile(_ profile: AIProviderProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        activeProfileId = profile.id
    }

    public mutating func deleteProfile(id: String) {
        profiles.removeAll(where: { $0.id == id })
        if activeProfileId == id {
            activeProfileId = profiles.first?.id ?? "gemini"
        }
    }

    // Các thuộc tính forward tương thích ngược hoàn toàn
    public var baseURL: String {
        get { activeProfile.baseURL }
        set {
            var p = activeProfile
            p.baseURL = newValue
            activeProfile = p
        }
    }

    public var apiKey: String {
        get { activeProfile.apiKey }
        set {
            var p = activeProfile
            p.apiKey = newValue
            activeProfile = p
        }
    }

    public var selectedModel: String {
        get { activeProfile.selectedModel }
        set {
            var p = activeProfile
            p.selectedModel = newValue
            activeProfile = p
        }
    }

    public var availableModels: [String] {
        get { activeProfile.availableModels }
        set {
            var p = activeProfile
            p.availableModels = newValue
            activeProfile = p
        }
    }

    public var temperature: Double {
        get { activeProfile.temperature }
        set {
            var p = activeProfile
            p.temperature = newValue
            activeProfile = p
        }
    }

    public var preset: AIProviderPreset {
        get {
            AIProviderPreset(rawValue: activeProfileId) ?? .custom
        }
        set {
            activeProfileId = newValue.rawValue
        }
    }

    enum CodingKeys: String, CodingKey {
        case profiles, activeProfileId, systemPrompt
        case preset, baseURL, apiKey, selectedModel, availableModels, temperature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? AIConfiguration.defaultSystemPrompt

        if let decodedProfiles = try container.decodeIfPresent([AIProviderProfile].self, forKey: .profiles), !decodedProfiles.isEmpty {
            self.profiles = decodedProfiles
            self.activeProfileId = try container.decodeIfPresent(String.self, forKey: .activeProfileId) ?? decodedProfiles.first?.id ?? "gemini"
        } else {
            // Nạp tương thích ngược từ cấu hình V1 cũ
            var defaultList = AIProviderProfile.defaultProfiles
            let legacyPreset = try container.decodeIfPresent(AIProviderPreset.self, forKey: .preset) ?? .gemini
            let legacyBaseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? legacyPreset.defaultBaseURL
            let legacyApiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
            let legacySelectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? ""
            let legacyModels = try container.decodeIfPresent([String].self, forKey: .availableModels) ?? legacyPreset.defaultModels
            let legacyTemp = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.3

            if let idx = defaultList.firstIndex(where: { $0.id == legacyPreset.rawValue }) {
                defaultList[idx].baseURL = legacyBaseURL
                defaultList[idx].apiKey = legacyApiKey
                defaultList[idx].selectedModel = legacySelectedModel.isEmpty ? defaultList[idx].selectedModel : legacySelectedModel
                defaultList[idx].availableModels = legacyModels
                defaultList[idx].temperature = legacyTemp
            }

            self.profiles = defaultList
            self.activeProfileId = legacyPreset.rawValue
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(activeProfileId, forKey: .activeProfileId)
        try container.encode(systemPrompt, forKey: .systemPrompt)
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
