import SwiftUI

/// Trình đọc dùng sheet chọn giọng chung `TTSVoicePickerSheet` — mọi trình đọc **trừ VieNeu** (sheet riêng
/// `VieNeuVoicePickerSheet`). `id` = giá trị `TTSManager.tool` tương ứng.
enum TTSVoiceEngine: Hashable, Identifiable {
    case siri
    case nghi
    case google
    /// vtts Việt–Anh (2026-11-20): 2 giọng có sẵn trong app, không tải / xoá.
    case vtts
    /// Tiện ích TTS — `packageId` là `tool` của trình đọc.
    case ext(packageId: String)

    /// `nil` cho VieNeu.
    init?(tool: String) {
        switch tool {
        case "vieneu": return nil
        case "system": self = .siri
        case "nghitts": self = .nghi
        case "google": self = .google
        case TTSManager.VttsSettings.tool: self = .vtts
        default: self = .ext(packageId: tool)
        }
    }

    var id: String {
        switch self {
        case .siri: return "system"
        case .nghi: return "nghitts"
        case .google: return "google"
        case .vtts: return TTSManager.VttsSettings.tool
        case .ext(let packageId): return packageId
        }
    }

    /// Siri, NghiTTS, vtts chạy trên máy ⇒ "Nhẹ"; Google, tiện ích ⇒ "Online".
    @MainActor
    var badge: TTSVoiceBadge {
        switch self {
        case .siri, .nghi, .vtts: return .light
        case .google, .ext: return .online
        }
    }

    /// Giải thích sau nút "?" của tiêu đề sheet.
    var helpText: [LocalizedStringKey] {
        switch self {
        case .siri:
            return ["Giọng Siri tải trong Cài đặt iOS › Trợ năng › Nội dung được đọc › Giọng nói › Tiếng Việt."]
        case .nghi:
            return ["Giọng Piper chạy trên máy, mỗi giọng một file khoảng 61 MB. Tải giọng đầu tiên thì tự tải luôn thư viện phiên âm. Xoá giọng đã tải bằng nút 🗑 cuối hàng (hoặc nhấn giữ)."]
        case .google:
            return ["Giọng đọc qua mạng, cần API key (ô nhập ở Cài đặt TTS). Thử giọng tính vào hạn mức của key."]
        case .vtts:
            return ["Giọng vtts có sẵn trong app, chạy trên máy, đọc được tiếng Việt, tiếng Anh và câu trộn hai thứ tiếng — không cần tải."]
        case .ext:
            return ["Danh sách giọng do tiện ích trả về. Thử giọng chạy đúng script của tiện ích."]
        }
    }
}
