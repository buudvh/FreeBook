import SwiftUI

/// Trình đọc dùng sheet chọn giọng chung `TTSVoicePickerSheet` — mọi trình đọc **trừ VieNeu** (sheet riêng
/// `VieNeuVoicePickerSheet`). `id` = giá trị `TTSManager.tool` tương ứng.
enum TTSVoiceEngine: Hashable, Identifiable {
    case siri
    case nghi
    case google
    /// Tiện ích TTS — `packageId` là `tool` của trình đọc.
    case ext(packageId: String)

    /// `nil` cho VieNeu.
    init?(tool: String) {
        switch tool {
        case "vieneu": return nil
        case "system": self = .siri
        case "nghitts": self = .nghi
        case "google": self = .google
        default: self = .ext(packageId: tool)
        }
    }

    var id: String {
        switch self {
        case .siri: return "system"
        case .nghi: return "nghitts"
        case .google: return "google"
        case .ext(let packageId): return packageId
        }
    }

    /// Siri, NghiTTS chạy trên máy ⇒ "Nhẹ"; Google, tiện ích ⇒ "Online".
    @MainActor
    var badge: TTSVoiceBadge {
        switch self {
        case .siri, .nghi: return .light
        case .google, .ext: return .online
        }
    }

    /// Giải thích sau nút "?" của tiêu đề sheet.
    var helpText: [LocalizedStringKey] {
        switch self {
        case .siri:
            return ["Giọng Siri tải trong Cài đặt iOS › Trợ năng › Nội dung được đọc › Giọng nói › Tiếng Việt."]
        case .nghi:
            return ["Giọng Piper chạy trên máy, mỗi giọng một file khoảng 61 MB. Tải giọng đầu tiên thì tự tải luôn thư viện phiên âm. Nhấn giữ giọng đã tải để xoá."]
        case .google:
            return ["Giọng đọc qua mạng, cần API key (ô nhập ở Cài đặt TTS). Thử giọng tính vào hạn mức của key."]
        case .ext:
            return ["Danh sách giọng do tiện ích trả về. Thử giọng chạy đúng script của tiện ích."]
        }
    }
}
