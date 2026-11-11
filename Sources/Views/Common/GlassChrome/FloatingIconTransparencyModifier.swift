import SwiftUI

/// Icon của **nút nổi** mờ theo "Độ trong suốt" của nút nổi (Cài đặt › Chung › Giao diện) — đúng số `1 − độ trong suốt`,
/// không sàn, như bìa đĩa nghe và icon nút hub / nút trình duyệt (anh Bửu chốt 2026-11-11: "Mờ, pill menu rõ").
///
/// Gắn lên **icon**, không lên nút: mờ trên lớp cha của nền kính `FloatingGlassBackground` là tắt nhoè của kính. Áp ở
/// `FloatingRoundButton` (nút "+", Home, nút bật menu xổ, Home ở Chi tiết), nút tai nghe Reader và ô xem trước ở Cài đặt ›
/// Giao diện. **Không** áp cho pill của menu xổ (`FloatingActionMenu`) — pill có chữ, chỉ hiện sau khi bấm "+".
struct FloatingIconTransparencyModifier: ViewModifier {
    @AppStorage(GlassChromeSettings.floatingTransparencyKey)
    private var transparency = GlassChromeSettings.defaultFloatingTransparency

    func body(content: Content) -> some View {
        content.opacity(1 - min(1, max(0, transparency)))
    }
}

extension View {
    /// Icon nút nổi mờ theo "Độ trong suốt" (`FloatingIconTransparencyModifier`).
    func floatingIconTransparency() -> some View {
        modifier(FloatingIconTransparencyModifier())
    }
}
