import Foundation

/// Một hàng của **sheet chọn giọng VieNeu** (1.3.899) — giọng Nano / Turbo, có sẵn hoặc tự tạo. Bản sao bất biến, dựng ở
/// `VieNeuVoiceDirectory` ngoài main; View chỉ vẽ.
struct VieNeuVoiceEntry: Identifiable, Hashable, Sendable {
    enum Group: Sendable {
        /// "Giọng của tôi" — giọng nhân bản của model đó.
        case mine
        /// "Giọng có sẵn" của Nano (11 giọng trong `voices_v3_nano.json`).
        case nanoPreset
        /// "Tuyển chọn" của Turbo (giọng ⭐ trong manifest).
        case turboFeatured
        /// "Giọng khác" của Turbo.
        case turboOther
    }

    /// Mức tốn CPU khi đọc (badge cạnh tên). Số đo ở nút "?" của sheet: Nano ~29 CPU-giây mỗi 1.000 ký tự, Turbo 37–43
    /// (Minh Quân Pro, Mai Anh — iPhone 11); Turbo có mẫu dài thì nặng hơn (ước tính, chưa đo từng giọng).
    enum Weight: Sendable {
        case light
        case medium
        case heavy

        /// Số khung 80 ms của mẫu tham chiếu từ đó Turbo tính là "Nặng" (mẫu ≥ 6,8 s): prefill dài hơn mỗi đoạn.
        static let heavyFrameThreshold = 85

        static func turbo(frames: Int?) -> Weight {
            (frames ?? 0) >= heavyFrameThreshold ? .heavy : .medium
        }

        var title: String {
            switch self {
            case .light: return "Nhẹ"
            case .medium: return "Vừa"
            case .heavy: return "Nặng"
            }
        }
    }

    let selection: VieNeuVoiceSelection
    let name: String
    /// Dòng phụ: "Nữ · Bắc · tin tức" hoặc "mẫu 8 s"; `nil` = không có.
    let detail: String?
    let weight: Weight
    let group: Group
    /// Giọng Nano tự tạo: id bản ghi ở `VieNeuCustomVoiceStore` (đổi tên / xoá / nghe mẫu gốc).
    let nanoRecordId: String?

    var id: String { selection.key }
    var model: VieNeuModelChoice { selection.model }
    var isMine: Bool { group == .mine }

    /// "Nữ · Bắc · Phong cách tin tức" ⇒ "Nữ · Bắc · tin tức" (bỏ chữ "Phong cách" / "Giọng đọc"), cùng cách rút gọn với
    /// `VieNeuTurboVoiceManifest.Voice.traitsSummary`. Chuỗi rỗng ⇒ `nil`.
    static func shortTraits(_ text: String) -> String? {
        let parts = text.components(separatedBy: " · ")
            .map { part -> String in
                var trimmed = part.trimmingCharacters(in: .whitespaces)
                for prefix in ["Phong cách ", "Giọng đọc "] where trimmed.hasPrefix(prefix) {
                    trimmed = String(trimmed.dropFirst(prefix.count))
                }
                return trimmed
            }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "mẫu 8 s" — độ dài mẫu giọng nhân bản.
    static func sampleDetail(seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return "mẫu \(Int(seconds.rounded())) s"
    }
}
