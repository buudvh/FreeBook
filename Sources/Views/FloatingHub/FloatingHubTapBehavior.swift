import Foundation

/// Cài đặt "Khi chạm hub" (Cài đặt › Chung › Giao diện › Hub nổi): chạm nút hub khi menu đang đóng thì làm gì.
///
/// - `alwaysMenu` (**mặc định**, người dùng chốt 2026-11-06): chạm luôn bung hub và mở menu đủ các dòng ở trang
///   chính, dù có 0, 1 hay nhiều tiến trình.
/// - `directWhenSingle`: bảng chạm theo số tiến trình chốt 2026-10-22 — 0 ⇒ màn Thông báo, 1 ⇒ mở thẳng mục đó, từ 2
///   ⇒ menu (`FloatingHubContainerViewController.activateByRunningTasks`).
///
/// Icon của nút cũng theo cài đặt (người dùng chốt 2026-11-06): `alwaysMenu` ⇒ **luôn** `square.stack.3d.up`;
/// `directWhenSingle` ⇒ icon theo số tiến trình như cũ (`FloatingHubButton.glyphName`). Nháy như nhau ở cả hai.
/// Chạm đọc `UserDefaults` lúc chạm (`current`), nút đọc bằng `@AppStorage` ⇒ đổi cài đặt là có hiệu lực ngay, không
/// cần publisher. Khoá không có dấu chấm (`@AppStorage` theo dõi bằng KVO); khoá chưa ghi hoặc giá trị lạ ⇒
/// `defaultValue`.
enum FloatingHubTapBehavior: String, CaseIterable, Identifiable {
    case alwaysMenu
    case directWhenSingle

    static let storageKey = "floatingHubTapBehavior"
    static let defaultValue: FloatingHubTapBehavior = .alwaysMenu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysMenu:
            return "Luôn hiện tất cả mục"
        case .directWhenSingle:
            return "Mở thẳng khi chỉ có 1 tác vụ"
        }
    }

    /// Giá trị đang lưu — đọc ở mỗi lần chạm nút hub.
    static var current: FloatingHubTapBehavior {
        UserDefaults.standard.string(forKey: storageKey).flatMap(FloatingHubTapBehavior.init(rawValue:)) ?? defaultValue
    }
}
