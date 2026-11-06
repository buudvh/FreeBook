import Foundation

/// Cài đặt "Khi chạm hub" (Cài đặt › Chung › Giao diện › Hub nổi): chạm nút hub khi menu đang đóng thì làm gì.
///
/// - `alwaysMenu` (**mặc định**, người dùng chốt 2026-11-06): chạm luôn bung hub và mở menu đủ các dòng ở trang
///   chính, dù có 0, 1 hay nhiều tiến trình.
/// - `directWhenSingle`: bảng chạm theo số tiến trình chốt 2026-10-22 — 0 ⇒ màn Thông báo, 1 ⇒ mở thẳng mục đó, từ 2
///   ⇒ menu (`FloatingHubContainerViewController.activateByRunningTasks`).
///
/// Chỉ đổi hành vi chạm: icon và nháy của nút vẫn theo số tiến trình ở cả hai lựa chọn. Đọc `UserDefaults` lúc chạm
/// (`current`) nên đổi cài đặt là có hiệu lực ngay, không cần publisher và nút không vẽ lại. Khoá không có dấu chấm
/// (`@AppStorage` theo dõi bằng KVO); khoá chưa ghi hoặc giá trị lạ ⇒ `defaultValue`.
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
