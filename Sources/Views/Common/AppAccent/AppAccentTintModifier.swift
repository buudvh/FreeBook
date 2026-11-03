import SwiftUI

/// Gắn màu nhấn người dùng chọn (`AppAccentColor`) cho cả cây view: `.tint` (nút, công tắc, vòng xoay, link, thanh tab
/// `MainTabBar`) **và** `.accentColor` (`Color.accentColor` của chip / viền đang chọn).
///
/// Gắn ở `MainTabView` và ở **gốc mọi cửa sổ / màn mở bằng UIKit** — những nơi đó không thừa hưởng `.tint` của
/// `MainTabView` (cửa sổ nổi TTS, hub, ngăn kéo `…`, trình phát video, trình duyệt Legado…). `@AppStorage` ⇒ chọn
/// màu ở Cài đặt là mọi nơi gắn modifier vẽ lại ngay.
///
/// Mỗi lần hiện ra và mỗi lần đổi màu cũng gán `tintColor` UIKit cho mọi cửa sổ (`applyToWindows()`): cửa sổ tạo sau
/// lúc mở app (ngăn kéo, hub, widget) có màu nhấn cho phần UIKit ngay khi gốc của nó hiện, không chờ lần đổi màu kế.
struct AppAccentTintModifier: ViewModifier {
    @AppStorage(AppAccentColor.storageKey) private var storedAccent = AppAccentColor.defaultValue.rawValue

    func body(content: Content) -> some View {
        let accent = AppAccentColor(storedValue: storedAccent)
        content
            .tint(accent.color)
            .accentColor(accent.color)
            .onChange(of: storedAccent, initial: true) { _, value in
                AppAccentColor(storedValue: value).applyToWindows()
            }
    }
}

extension View {
    func appAccentTint() -> some View {
        modifier(AppAccentTintModifier())
    }
}
