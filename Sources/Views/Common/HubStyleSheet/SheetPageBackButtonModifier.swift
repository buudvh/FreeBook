import SwiftUI

/// Nút **‹** của **trang con trong sheet** (2026-11-11, anh Bửu: "chuyển sheet giống sheet hub vào sheet tác vụ AI"): sheet
/// kiểu hub (`HubStyleActionSheet`) và sheet hub (`FloatingHubSheet`) chuyển trang ngay trong sheet, trang con có nút ‹ ở
/// góc trái header để về trang chính.
///
/// Người dựng trang đặt hành động qua `.environment(\.sheetPageBack, …)`; trang gắn `.sheetPageBackButton()` **bên trong**
/// `NavigationStack` của nó (toolbar ngoài stack không tới được thanh điều hướng). Không có hành động ⇒ không có nút, nên
/// màn dùng chung (`NotificationInboxView`, màn kiểm tra nguồn) mở ở chỗ khác vẫn như cũ.
struct SheetPageBackButtonModifier: ViewModifier {
    @Environment(\.sheetPageBack) private var back

    func body(content: Content) -> some View {
        content.toolbar {
            if let back {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 38, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Quay lại")
                }
            }
        }
    }

    /// Khoá environment lồng trong type (một type chính mỗi file).
    struct Key: EnvironmentKey {
        static var defaultValue: (() -> Void)? { nil }
    }
}

extension EnvironmentValues {
    /// Hành động của nút ‹ trang con trong sheet; `nil` ⇒ màn không nằm trong trang con.
    var sheetPageBack: (() -> Void)? {
        get { self[SheetPageBackButtonModifier.Key.self] }
        set { self[SheetPageBackButtonModifier.Key.self] = newValue }
    }
}

extension View {
    /// Nút ‹ về trang chính khi màn là trang con trong sheet (`sheetPageBack` có giá trị).
    func sheetPageBackButton() -> some View {
        modifier(SheetPageBackButtonModifier())
    }
}
