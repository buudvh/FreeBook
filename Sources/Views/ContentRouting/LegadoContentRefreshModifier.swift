import SwiftUI

/// Nghe `LegadoContentRefreshSignal` cho nguồn `packageId` của sách đang mở và gọi `action` (nạp lại chương hiện tại,
/// bỏ qua cache) khi nguồn đó phát `refreshContent()`. Đọc tín hiệu trong modifier riêng để chỉ modifier này — không
/// phải cả màn đọc — vẽ lại khi bộ đếm đổi. Chỉ phản ứng với tín hiệu **sau** khi màn đã mở (`onChange`, không `initial`).
/// Sách của tiện ích JS: bộ đếm không bao giờ đổi, modifier không làm gì.
struct LegadoContentRefreshModifier: ViewModifier {
    let packageId: String
    let action: () -> Void

    func body(content: Content) -> some View {
        let serial = LegadoContentRefreshSignal.shared.serial(packageId: packageId)
        return content
            .onChange(of: serial) { _, _ in
                AppLogger.shared.log("📚 [LegadoRefresh] Nguồn yêu cầu nạp lại chương đang đọc")
                action()
            }
    }
}

extension View {
    /// Nạp lại chương đang đọc khi nguồn Legado `packageId` gọi `refreshContent()` — xem `LegadoContentRefreshModifier`.
    func legadoContentRefresh(packageId: String, perform action: @escaping () -> Void) -> some View {
        modifier(LegadoContentRefreshModifier(packageId: packageId, action: action))
    }
}
