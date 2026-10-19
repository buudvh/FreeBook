import UIKit

/// Cách tắt bàn phím khi **chạm ra ngoài ô nhập**: tự tắt (mặc định, hành vi trước khi có tuỳ chọn) hoặc không tắt
/// — khi đó tắt bằng nút đóng bàn phím ở thanh công cụ trên bàn phím (phím Return của ô một dòng và kéo danh sách
/// vẫn tắt như iOS vốn có).
///
/// Chỉnh ở hai chỗ: giữ nút đóng bàn phím (`KeyboardTextToolbarView`) và Cài đặt → Bàn phím & ô nhập
/// (`KeyboardSettingsView`). Cả hai ghi qua `setTapOutsideDismisses(_:)` để `KeyboardDismissGesture` áp dụng ngay,
/// kể cả khi bàn phím đang mở.
enum KeyboardDismissPreference {
    /// Khoá chữ thường ⇒ `BackupSettingsArchiver` tự gói vào bản sao lưu.
    static let tapOutsideDismissesKey = "keyboardDismissOnTapOutside"

    static var tapOutsideDismisses: Bool {
        UserDefaults.standard.object(forKey: tapOutsideDismissesKey) as? Bool ?? true
    }

    @MainActor
    static func setTapOutsideDismisses(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: tapOutsideDismissesKey)
        KeyboardDismissGesture.shared.applyPreference()
    }

    /// Cho các màn tự gắn "chạm nền là tắt bàn phím" riêng (panel Dịch, panel xoá rác, sheet công cụ tìm kiếm, vùng
    /// trống trình sửa Script): chỉ tắt khi tuỳ chọn là "Tự tắt" — trước đây các màn này tắt bất kể tuỳ chọn.
    @MainActor
    static func dismissOnTapOutsideIfEnabled() {
        guard tapOutsideDismisses else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
