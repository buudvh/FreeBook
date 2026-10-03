import Foundation

/// Cấu hình kết nối tới OpenAI-compatible API với quản lý đa Profile.
public struct AIConfiguration: Codable, Sendable, Equatable {
    public var profiles: [AIProviderProfile]
    public var activeProfileId: String
    public var systemPrompt: String
    public var nameExtractionPrompt: String

    public init(
        profiles: [AIProviderProfile] = [],
        activeProfileId: String = "gemini",
        systemPrompt: String = AIConfiguration.defaultSystemPrompt,
        nameExtractionPrompt: String = AIConfiguration.defaultNameExtractionPrompt
    ) {
        self.profiles = profiles
        self.activeProfileId = activeProfileId
        self.systemPrompt = systemPrompt
        self.nameExtractionPrompt = nameExtractionPrompt
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
            activeProfileId = profiles.first?.id ?? ""
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
        case profiles, activeProfileId, systemPrompt, nameExtractionPrompt
        case preset, baseURL, apiKey, selectedModel, availableModels, temperature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? AIConfiguration.defaultSystemPrompt
        self.nameExtractionPrompt = try container.decodeIfPresent(String.self, forKey: .nameExtractionPrompt) ?? AIConfiguration.defaultNameExtractionPrompt

        if let decodedProfiles = try container.decodeIfPresent([AIProviderProfile].self, forKey: .profiles) {
            // Chỉ giữ lại những profile người dùng thêm hoặc đã cấu hình có API key
            let valid = decodedProfiles.filter { $0.isCustom || !$0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            self.profiles = valid
            self.activeProfileId = try container.decodeIfPresent(String.self, forKey: .activeProfileId) ?? valid.first?.id ?? ""
        } else {
            self.profiles = []
            self.activeProfileId = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(activeProfileId, forKey: .activeProfileId)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(nameExtractionPrompt, forKey: .nameExtractionPrompt)
    }

    public static let defaultSystemPrompt: String = """
    Bạn là AI Trợ Lý đọc truyện chuyên nghiệp tích hợp trong app FreeBook (FreeBook AI Harness).
    Nhiệm vụ của bạn là:
    - Trả lời, tóm tắt, giải thích bối cảnh, phân tích nhân vật và tình tiết truyện một cách chính xác, hấp dẫn.
    - Trích xuất tên riêng (Nhân vật, Địa danh, Tông môn, Công pháp...) từ văn bản raw tiếng Trung chưa dịch.
    - Tuân thủ chế độ quyền hạn của người dùng (Ask, Plan, Bypass) khi gọi các công cụ sửa đổi dữ liệu truyện.
    """

    public static let defaultNameExtractionPrompt: String = """
    Hãy trích xuất tất cả tên riêng trong văn bản, gồm tên người, địa danh, tổ chức, môn phái, công pháp, bảo vật và các thực thể có tên riêng.

    FORMAT ĐẦU RA BẮT BUỘC:

    * Mỗi thực thể xuất hiện trên một dòng riêng.
    * Mỗi dòng có đúng dạng:
    Tên gốc=Nghĩa tiếng Việt
    * Không thêm số thứ tự, dấu đầu dòng, dấu ngoặc kép hoặc ký hiệu khác.
    * Giữ nguyên tên gốc bằng chữ Hán ở bên trái dấu "=".
    * Bên phải dấu "=" là cách dịch, Hán Việt hoặc phiên âm phù hợp.
    * Nếu một tên xuất hiện nhiều lần thì chỉ xuất ra một lần.
    * Nếu không tìm thấy tên riêng nào, chỉ trả về:
    Không có name
    * Không thêm bất kỳ lời giải thích, nhận xét hoặc nội dung nào khác.

    QUY TẮC CHUẨN HOÁ:

    * Tên Trung Quốc → Hán Việt.
    * Tên Nhật, Hàn, Anh hoặc tên ngoại quốc viết bằng chữ Hán → dùng cách đọc/phiên âm đúng theo ngôn ngữ gốc, không đọc Hán Việt máy móc.
    * Dạng “Họ/Tên + đại từ nhân xưng/chức danh/cách gọi” → giữ đúng thứ tự Họ/Tên + cách gọi tiếng Việt.
    * Ví dụ:
    何老三=Hà lão tam
    李掌柜=Lý chưởng quầy
    李医生=Lý bác sĩ
    陈教授=Trần giáo sư
    王老板=Vương lão bản
    * Không đảo thứ tự thành “bác sĩ Lý”, “giáo sư Trần”...
    """

    /// Nhận diện prompt trích xuất dạng JSON cũ để di trú sang dạng "Tên gốc=Nghĩa".
    public static func looksLikeLegacyJSONNameExtractionPrompt(_ text: String) -> Bool {
        let markers = ["suggestedMeaning", "extracted_names", "JSON hợp lệ"]
        return markers.contains { text.contains($0) }
    }

    public static var `default`: AIConfiguration {
        AIConfiguration()
    }
}
