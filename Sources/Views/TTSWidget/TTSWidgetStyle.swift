import Foundation

/// Kiểu hiển thị của widget TTS nổi (Cài đặt › Đọc & Nghe › Widget TTS, 1.3.796). Lưu `rawValue` ở khoá
/// `TTSWidgetPreferences.styleKey`; khoá vắng / giá trị lạ ⇒ `.disc`.
enum TTSWidgetStyle: String, CaseIterable, Identifiable {
    /// Đĩa tròn nép mép ↔ viên capsule tự ẩn (`FloatingWidgetContainerViewController`) — kiểu có từ trước, mặc định.
    case disc
    /// Thanh dáng thanh phát mini nghe nhạc ngay trên thanh tab, thu gọn được thành viên nép mép phải
    /// (`TTSWidgetBarContainerViewController`).
    case bar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disc: return "Đĩa nổi"
        case .bar: return "Thanh nghe nhạc"
        }
    }
}
