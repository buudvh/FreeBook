import SwiftUI

/// Một **dòng** của nút hub nổi (1.3.524; 1.3.533 đổi sang tập dòng cố định): lối tắt tới một việc đang chạy
/// nền mà người dùng có thể quay lại.
///
/// ## Tập dòng cố định
/// Menu luôn có đủ `Kind.allCases` (AI → Thông báo → Video), mục nào không dùng được thì **xám** chứ không
/// biến mất. `FloatingHubPresentationReader` là nơi duy nhất quyết định trạng thái từng dòng; type này chỉ mô
/// tả dòng trông ra sao. Trình duyệt thu nhỏ đã rời hub, quay về cửa sổ riêng (`BrowserFloatingWidgetWindowManager`).
///
/// Mọi thứ hàng cần vẽ đều nằm trên item (`isEnabled`, `title`, `detail`, `badgeCount`, `isPlaying`), nên
/// đường `snapshot.items` → `removeDuplicates()` của container bắt được mọi đổi trạng thái của menu. Các trường
/// này **không** đi vào `FloatingHubPresentationReader.ButtonState`: tiêu đề AI đổi theo từng batch hay video
/// phát/dừng không làm vẽ lại nút.
struct FloatingHubItem: Equatable, Identifiable {
    /// Loại dòng. Thứ tự khai báo là **thứ tự hiển thị cố định** trong menu: AI → Thông báo → Video.
    enum Kind: Int, CaseIterable {
        case ai
        case notifications
        case video

        var title: String {
            switch self {
            case .ai:
                return "Trợ lý AI"
            case .notifications:
                return "Thông báo"
            case .video:
                return "Video"
            }
        }

        /// Glyph SF Symbols của dòng. Chuông đặc khi còn thông báo chưa đọc, chuông trơn khi không.
        func systemImage(unreadCount: Int) -> String {
            switch self {
            case .ai:
                return "sparkles"
            case .notifications:
                // `bell.fill` chứ không `bell.badge.fill`: dòng tự vẽ chấm đỏ chưa đọc lên icon (`FloatingHubMenuRow`),
                // icon có chấm sẵn là hai chấm chồng nhau.
                return unreadCount > 0 ? "bell.fill" : "bell"
            case .video:
                return "play.rectangle"
            }
        }

        /// AI dùng icon trắng (người dùng chốt 2026-10-17); hai dòng kia theo màu chữ hệ thống.
        var tint: Color {
            switch self {
            case .ai:
                return .white
            case .notifications, .video:
                return .primary
            }
        }
    }

    let kind: Kind
    /// Dòng dùng được: chạm được. `false` ⇒ dòng xám, không chạm được — dòng
    /// **vẫn nằm đó**, không bị bỏ khỏi menu.
    var isEnabled = false
    /// Dòng chính; rỗng ⇒ dùng `kind.title`. Mục Video đặt tên phim vào đây.
    var headline = ""
    /// Dòng phụ một dòng. Reader luôn điền chữ (kể cả lúc xám) để chiều cao dòng không đổi.
    var detail = ""
    /// Số trên badge của dòng (Thông báo: số chưa đọc). 0 ⇒ badge trong suốt, không bị bỏ khỏi cây view.
    var badgeCount = 0
    /// Chỉ mục Video dùng: đang phát hay đang dừng (glyph của nút phát/dừng).
    var isPlaying = false
    /// Đang có việc. Với AI và Video, cờ này là "tiến trình" của nút hub (icon, nháy, chạm); Thông báo thì nút hub
    /// chỉ tính tác vụ nền, không đọc cờ này. Tách khỏi `isEnabled` vì Thông báo **luôn** chạm được nhưng chỉ tính
    /// là "đang hoạt động" khi có tin chưa đọc hoặc tác vụ chạy.
    var isActive = false

    var id: Kind { kind }

    /// Chữ hiển thị ở dòng chính.
    var title: String { headline.isEmpty ? kind.title : headline }
}
