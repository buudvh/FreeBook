import UIKit

/// Sổ các **neo** của đĩa nghe (`MediaDiscWindowManager`, 1.3.808): những thứ ở đáy màn mà nửa viên đĩa dính mép phải
/// **né** — đè lên thì tạm đẩy lên ngay trên (nút "+" / Home / menu xổ / FAB Chi tiết, nút tai nghe Reader, thanh dưới trình
/// duyệt, thanh dưới truyện tranh) — và những màn phải **ẩn** đĩa (màn xem phim, trang có thanh tab).
///
/// Mỗi neo là một `MediaDiscAnchorProbe` (UIView 0 chạm, nằm sau view thật nên khung = khung neo) tự đăng ký khi vào cửa sổ
/// và tự gỡ khi SwiftUI bỏ view. Sổ chỉ giữ tham chiếu **yếu**; neo nào hợp lệ lúc này (đúng cửa sổ chính, đúng tầng trình
/// bày trên cùng, nằm trong màn) do `MediaDiscPlacement.resolve` xét lại mỗi lượt — sổ không tự đoán.
///
/// `onChange` (container của đĩa gắn) được gọi **gộp một lượt main** sau mỗi lần neo vào / rời cửa sổ / đổi cỡ, không bao
/// giờ gọi đồng bộ trong lượt cập nhật của SwiftUI.
@MainActor
final class MediaDiscAnchorRegistry {
    enum Role {
        /// Nút / cụm nút nổi góc dưới phải: đĩa cùng cột mà đè lên ⇒ tạm đẩy lên trên nút.
        case button
        /// Thanh ngang sát đáy màn: đĩa đè lên (ở mép nào cũng vậy) ⇒ tạm đẩy lên trên thanh.
        case bar
        /// Màn che đĩa (màn xem phim): neo này hợp lệ ⇒ ẩn đĩa.
        case blocker
        /// Màn tự có chỗ đặt đĩa (thanh tab `MainTabBar` có ô đĩa ở giữa, 1.3.812): neo này hợp lệ ⇒ ẩn đĩa góc **ngay**.
        case hostsDisc
    }

    struct Anchor {
        let view: UIView
        let role: Role
    }

    private struct Entry {
        weak var view: UIView?
        let role: Role
    }

    static let shared = MediaDiscAnchorRegistry()

    /// Container của đĩa gắn: tính lại chỗ đĩa.
    var onChange: (() -> Void)?

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var isChangeScheduled = false

    private init() {}

    func register(_ view: UIView, role: Role) {
        entries[ObjectIdentifier(view)] = Entry(view: view, role: role)
        noteChange()
    }

    func unregister(_ view: UIView) {
        guard entries.removeValue(forKey: ObjectIdentifier(view)) != nil else { return }
        noteChange()
    }

    /// Neo còn sống (view chưa bị giải phóng). Bỏ luôn mục đã chết.
    var anchors: [Anchor] {
        var alive: [Anchor] = []
        var dead: [ObjectIdentifier] = []
        for (key, entry) in entries {
            if let view = entry.view {
                alive.append(Anchor(view: view, role: entry.role))
            } else {
                dead.append(key)
            }
        }
        for key in dead { entries[key] = nil }
        return alive
    }

    /// Báo đổi — gộp mọi lần báo trong cùng nhịp main thành một lần gọi `onChange`.
    func noteChange() {
        guard !isChangeScheduled else { return }
        isChangeScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isChangeScheduled = false
                self.onChange?()
            }
        }
    }
}
