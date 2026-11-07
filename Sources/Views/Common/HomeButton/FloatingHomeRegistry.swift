import Observation
import UIKit

/// Ai trên mỗi trang đang giữ **nút Home nổi** — khoá theo trang (`FloatingHomePlacement.hostID`), không theo cây SwiftUI.
///
/// Vì sao không dùng preference / environment: thứ tự `.floatingAddButton` và `.pageTitle` ở các màn lẫn lộn (nút "+"
/// khi nằm trong, khi nằm ngoài tiêu đề), preference chỉ đi lên còn environment đi xuống lại **rò** sang trang đẩy tiếp
/// và sheet; FAB của Chi tiết truyện còn là anh em của nội dung trong `ZStack`. Hai bên cùng hỏi cây UIKit "tôi ở trang
/// nào" (`FloatingHomeProbe`) rồi gặp nhau ở đây thì thứ tự nào cũng đúng.
///
/// - `.addButton`: nút "+" nổi / FAB riêng của trang — Home nằm trong menu xổ của nó ⇒ tiêu đề không vẽ Home tròn riêng.
/// - `.pageTitle`: `FloatingHomeButtonModifier` (gắn trong `PageTitleModifier`) — vẽ Home tròn khi trang không có
///   `.addButton`; trang lỡ có hai tiêu đề lồng nhau thì chỉ người đăng ký sớm nhất vẽ.
///
/// Mục tự hết hiệu lực khi trang bị giải phóng (giữ VC bằng tham chiếu yếu, không tin `ObjectIdentifier` có thể bị dùng
/// lại); gỡ hẳn khi SwiftUI gỡ đầu dò (`dismantleUIView`).
@MainActor
@Observable
final class FloatingHomeRegistry {
    enum Role {
        case addButton
        case pageTitle
    }

    private struct Entry {
        let role: Role
        let hostID: ObjectIdentifier
        weak var host: UIViewController?
        let order: Int

        var isAlive: Bool { host != nil }
    }

    static let shared = FloatingHomeRegistry()

    private var entries: [UUID: Entry] = [:]
    @ObservationIgnored private var nextOrder = 0

    private init() {}

    func register(_ token: UUID, role: Role, host: UIViewController) {
        let hostID = ObjectIdentifier(host)
        if let existing = entries[token], existing.role == role, existing.hostID == hostID, existing.host === host {
            return
        }
        nextOrder += 1
        var updated = entries.filter { $0.value.isAlive }
        updated[token] = Entry(role: role, hostID: hostID, host: host, order: nextOrder)
        entries = updated
    }

    func unregister(_ token: UUID) {
        guard entries[token] != nil else { return }
        entries[token] = nil
    }

    /// Trang `hostID` có nút "+" nổi / FAB riêng (Home nằm trong menu của nó).
    func hasAddButton(on hostID: ObjectIdentifier) -> Bool {
        entries.values.contains { $0.role == .addButton && $0.hostID == hostID && $0.isAlive }
    }

    /// `token` là tiêu đề được vẽ Home tròn riêng của trang `hostID` (tiêu đề đăng ký sớm nhất còn sống).
    func drawsPageTitleHome(_ token: UUID, on hostID: ObjectIdentifier) -> Bool {
        let owner = entries
            .filter { $0.value.role == .pageTitle && $0.value.hostID == hostID && $0.value.isAlive }
            .min { $0.value.order < $1.value.order }
        return owner?.key == token
    }
}
