import SwiftUI

/// Hành động nút **‹** của **trang con trong sheet** (2026-11-11, anh Bửu: "chuyển sheet giống sheet hub vào sheet tác vụ
/// AI"): sheet kiểu hub (`HubStyleActionSheet`) và sheet hub (`FloatingHubSheet`) chuyển trang ngay trong sheet, trang con
/// có nút ‹ ở góc trái header để về trang chính.
///
/// Người dựng trang đặt hành động qua `.environment(\.sheetPageBack, …)` **bên ngoài** `NavigationStack` của trang. Trang
/// dùng `.pageTitle(_:style: .centered)` / `.backPageTitle(_:)`: `PageTitleModifier` thấy giá trị ⇒ dựng nút ‹
/// (`HeaderBackButton`) và tiêu đề **chung một** `ToolbarItem` (1.3.1018). Không có giá trị ⇒ không có nút, nên màn dùng
/// chung (`NotificationInboxView`, màn kiểm tra nguồn) mở ở chỗ khác vẫn như cũ.
///
/// Trước 1.3.1018 trang tự gắn `.sheetPageBackButton()` (một `ToolbarItem` riêng) — đã bỏ: hai mục `topBarLeading` riêng
/// thì iOS tự xếp thứ tự / giãn cách, không bảo đảm ‹ đứng trước tiêu đề.
enum SheetPageBackEnvironment {
    /// Khoá environment lồng trong type (một type chính mỗi file).
    struct Key: EnvironmentKey {
        static var defaultValue: (() -> Void)? { nil }
    }
}

extension EnvironmentValues {
    /// Hành động của nút ‹ trang con trong sheet; `nil` ⇒ màn không nằm trong trang con.
    var sheetPageBack: (() -> Void)? {
        get { self[SheetPageBackEnvironment.Key.self] }
        set { self[SheetPageBackEnvironment.Key.self] = newValue }
    }
}
