import Foundation

/// Một dòng con của màn Dung lượng: loại "Giọng đọc & từ điển TTS" và "Khác" bấm vào thì bung ra các dòng này
/// (`StorageUsageTTSBreakdown`, `StorageUsageHomeBreakdown`). Đo cùng lượt với loại cha, nên cộng các dòng con của một
/// loại luôn ra đúng số của loại đó.
///
/// `Codable` vì nằm trong `StorageUsageSnapshot` đã lưu: thêm `Kind` mới thì bản đo cũ không giải được ⇒ snapshot cũ bị
/// bỏ, màn đo lại — chấp nhận được. Trường mới thì để tuỳ chọn (`var … = nil`, như `children`) để bản đo cũ vẫn giải được.
public struct StorageUsageDetail: Sendable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        // Thuộc `.tts` (cả `Application Support/FreeBook`).
        case vieNeuNano
        case vieNeuNanoCoreML
        case vieNeuTurbo
        case clonedVoices
        case nghiTTS
        case ttsDictionaries
        case ttsJunk
        case ttsOther
        // Thuộc `.other` (thư mục nhà trừ mọi loại đã liệt kê).
        case temporary
        case systemCaches
        case webData
        case unknown

        public var category: StorageUsageCategory {
            switch self {
            case .vieNeuNano, .vieNeuNanoCoreML, .vieNeuTurbo, .clonedVoices, .nghiTTS, .ttsDictionaries, .ttsJunk,
                 .ttsOther:
                return .tts
            case .temporary, .systemCaches, .webData, .unknown:
                return .other
            }
        }
    }

    public let kind: Kind
    public let bytes: Int64
    /// Số giọng (VieNeu Nano / Turbo, Piper) khi đếm được rẻ; `nil` = không ghi số.
    public let count: Int?
    /// Dòng cháu (chỉ "Bộ đệm hệ thống" và "Không rõ chủ"), cộng lại đúng bằng `bytes`. `nil` ở bản đo cũ / dòng khác.
    /// Phải là `var … = nil` (không phải `let`): `Decodable` tự sinh bỏ qua `let` có giá trị đầu.
    public var children: [StorageUsageSubItem]? = nil

    public var id: String { kind.rawValue }

    /// Phần "không còn dùng" — dọn ở trang Dọn rác, vẽ màu cam.
    public var isJunk: Bool { kind == .ttsJunk }

    public var title: String {
        switch kind {
        case .vieNeuNano:
            if let count, count > 0 { return "VieNeu Nano · model + \(count) giọng" }
            return "VieNeu Nano · model"
        case .vieNeuNanoCoreML:
            return "VieNeu Nano · Tăng tốc Core ML"
        case .vieNeuTurbo:
            if let count, count > 0 { return "VieNeu Turbo · model + \(count) giọng" }
            return "VieNeu Turbo · model"
        case .clonedVoices:
            return "Giọng nhân bản (Nano, Turbo)"
        case .nghiTTS:
            if let count, count > 0 { return "NghiTTS · \(count) giọng Piper" }
            return "NghiTTS · giọng Piper"
        case .ttsDictionaries:
            return "Từ điển phiên âm (NghiTTS, VieNeu)"
        case .ttsJunk:
            return "Không còn dùng · dọn ở Dọn rác"
        case .ttsOther:
            return "Khác của TTS"
        case .temporary:
            return "File tạm (tmp)"
        case .systemCaches:
            return "Bộ đệm hệ thống (Library/Caches)"
        case .webData:
            return "Dữ liệu web (đăng nhập, cookie)"
        case .unknown:
            return "Không rõ chủ · chỉ hiện, không tự xoá"
        }
    }
}
