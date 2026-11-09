import Foundation

/// Kiểu hiển thị của widget TTS nổi (Cài đặt › Đọc & Nghe › Widget TTS, 1.3.796; đổi kiểu thứ hai ở 1.3.808). Lưu
/// `rawValue` ở khoá `TTSWidgetPreferences.styleKey`; khoá vắng / giá trị lạ ⇒ `.disc`.
enum TTSWidgetStyle: String, CaseIterable, Identifiable {
    /// Đĩa tròn nép mép ↔ viên capsule tự ẩn (`FloatingWidgetContainerViewController`) — kiểu có từ trước, mặc định.
    case disc
    /// Đĩa xoay góc dưới phải dùng chung với trình nghe nhạc (`MediaDiscWindowManager`), chạm mở sheet điều khiển nhanh.
    /// Giữ raw value `"bar"` của kiểu "Thanh nghe nhạc" cũ (1.3.796–807) ⇒ ai đang chọn thanh tự sang kiểu này.
    case cornerDisc = "bar"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disc: return "Đĩa nổi"
        case .cornerDisc: return "Đĩa góc dưới"
        }
    }
}
