import Foundation

/// Kiểu thu nhỏ khi **vuốt xuống** khung phim ở màn dọc (Cài đặt › Đọc & Nghe › Video, ghi đè theo tiện ích ở mục Video
/// của Cấu hình tiện ích). Nút ⌄ không theo tuỳ chọn này: luôn thu nhỏ vào hub. Cả hai kiểu đều co khung phim theo tay
/// (`VideoMinimizeDragState`) rồi mới tới đích.
///
/// Lưu bằng raw value (`UserDefaults` của cài đặt chung, `Extension.videoMinimizeOverride` của tiện ích) — đổi raw value
/// là mất lựa chọn đã lưu. `miniPlayer` giữ raw value `"pictureInPicture"` của kiểu Hình trong hình cũ (bỏ ở 1.3.751).
enum VideoMinimizeStyle: String, CaseIterable, Identifiable, Sendable {
    /// Màn đóng, phim chạy nền, hub hiện mục Video; khung phim bay vào nút hub.
    case hub
    /// Cửa sổ phim nhỏ trong app (`VideoMiniPlayerWindowManager`). Phim nhúng trang ⇒ hub.
    case miniPlayer = "pictureInPicture"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hub: return "Thu nhỏ vào hub"
        case .miniPlayer: return "Cửa sổ nhỏ"
        }
    }
}
