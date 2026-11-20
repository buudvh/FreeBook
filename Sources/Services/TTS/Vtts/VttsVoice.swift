import Foundation

/// Giọng của trình đọc **vtts Việt–Anh (Offline)** — 2 giọng bản M của release v0.4.0, lưu sẵn trong repo
/// (`Vendor/vtts/assets/vtts`) và đóng vào IPA (thư mục `vtts/` của bundle). Không tải / xoá: chỉ chọn.
///
/// `rawValue` là id lưu trong cài đặt và là tham số `voice` của `LocalTTSEngine` (`VttsTTSService`) — đổi `rawValue` là
/// mất lựa chọn đã lưu. Id lạ (giọng của trình đọc khác lọt sang, dữ liệu cũ) ⇒ `resolve` trả giọng mặc định.
enum VttsVoice: String, CaseIterable, Identifiable {
    case nu10 = "nu-10"
    case nam1 = "nam-1"

    static let defaultVoice: VttsVoice = .nu10

    var id: String { rawValue }

    /// Tên hiện ở Picker / sheet Giọng đọc.
    var displayName: String {
        switch self {
        case .nu10: return "Nữ · nu-10"
        case .nam1: return "Nam · nam-1"
        }
    }

    /// Dòng phụ: ngôn ngữ đọc được + dung lượng model (2 580 320 byte mỗi giọng).
    var detail: String { "Việt + Anh · 2,6 MB" }

    /// Tên file model trong thư mục `vtts` của bundle — giữ đúng tên ở release upstream (`Scripts/ci/check_vtts_assets.sh`
    /// kiểm SHA256 theo tên này với `SHA256SUMS` của release).
    var modelFileName: String {
        switch self {
        case .nu10: return "vtts-vien-nu10-m-v0.4.q8.vtts"
        case .nam1: return "vtts-vien-nam1-m-v0.4.q8.vtts"
        }
    }

    static func resolve(_ id: String) -> VttsVoice {
        VttsVoice(rawValue: id) ?? defaultVoice
    }
}
