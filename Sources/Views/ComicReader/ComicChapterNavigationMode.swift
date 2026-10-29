import Foundation

/// Cách chuyển chương ở màn đọc truyện tranh (1.3.643), chọn ở ngăn kéo "…" của màn đọc.
///
/// - `tapSides` (mặc định): chạm 1/3 trái ⇒ chương trước, 1/3 phải ⇒ chương sau, 1/3 giữa bật/tắt thanh điều khiển.
///   Vuốt ngang không đổi chương. Chạm đúp vẫn mở trình xem phóng to.
/// - `swipe`: kiểu cũ (1.3.613) — vuốt ngang ở bất kỳ đâu (trái ⇒ chương sau), chạm ở đâu cũng chỉ bật/tắt thanh.
enum ComicChapterNavigationMode: String, CaseIterable, Identifiable {
    case tapSides = "tap"
    case swipe = "swipe"

    /// Khoá `@AppStorage` (không dấu chấm — bài học 1.3.637).
    static let storageKey = "comicChapterNavigationMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tapSides: return "Chạm hai bên"
        case .swipe: return "Vuốt ngang"
        }
    }
}
