import Foundation

/// Kiểu thu nhỏ khi **vuốt xuống** khung phim ở màn dọc (Cài đặt › Đọc & Nghe › Video, ghi đè theo tiện ích ở mục Video
/// của Cấu hình tiện ích). Nút ⌄ không theo tuỳ chọn này: luôn thu nhỏ vào hub.
///
/// Lưu bằng raw value (`UserDefaults` của cài đặt chung, `Extension.videoMinimizeOverride` của tiện ích) — đổi tên case
/// là mất lựa chọn đã lưu.
enum VideoMinimizeStyle: String, CaseIterable, Identifiable, Sendable {
    /// Màn đóng, phim chạy nền, hub hiện mục Video (hành vi trước 1.3.740).
    case hub
    /// Bật Hình trong hình; màn tự thu nhỏ khi PiP đã bật. Không bật được (phim nhúng, item chưa sẵn sàng) ⇒ hub.
    case pictureInPicture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hub: return "Thu nhỏ vào hub"
        case .pictureInPicture: return "Hình trong hình"
        }
    }
}
