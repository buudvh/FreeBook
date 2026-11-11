import Combine
import Foundation

/// Trạng thái **sheet hub** (2026-11-11): đang mở hay không, trang đang hiện, chiều cao nội dung đo được (giữ qua các lần
/// mở, khuôn `AudioQuickControlSheet.height`), và việc phải làm **sau khi** sheet đóng xong.
///
/// - Mở: `present(page:)` (container gọi khi chạm nút hub).
/// - Đóng: `dismiss(then:)` — đặt `isPresented = false`; `didDismiss()` (gắn ở `onDismiss` của `.sheet`) chạy cả khi người
///   dùng vuốt xuống lẫn khi đóng bằng code (luật 26: mọi đường đóng phải hạ cờ). Việc kèm theo (mở màn Thông báo, màn AI,
///   phim, Reader) chạy **sau** khi sheet đã đóng xong — trình bày từ sheet đang đóng thì UIKit đóng luôn màn mới. Thông
///   báo và Kiểm tra nguồn là trang con trong sheet (1.3.872), không phải việc kèm theo.
/// - `onPresentedChange` (container gắn) báo `FloatingHubWindowManager.setSheetPresented` để giữ cửa sổ hub + giấu nút
///   trong lúc sheet mở. Báo `false` **trước** khi chạy việc kèm theo: việc đó có thể mở sheet Thông báo (báo lại `true`).
@MainActor
final class FloatingHubSheetState: ObservableObject {
    @Published var isPresented = false
    @Published var page: FloatingHubSheet.Page = .main
    @Published var contentHeight: CGFloat = 0

    var onPresentedChange: ((Bool) -> Void)?

    private var afterDismiss: (() -> Void)?

    func present(page: FloatingHubSheet.Page) {
        self.page = page
        afterDismiss = nil
        guard !isPresented else { return }
        AppLogger.shared.log("🪟 [FloatingHub] Mở sheet hub (trang \(page))")
        onPresentedChange?(true)
        isPresented = true
    }

    /// Đóng sheet rồi mới chạy `action`; sheet không mở ⇒ chạy luôn.
    func dismiss(then action: (() -> Void)? = nil) {
        guard isPresented else {
            action?()
            return
        }
        afterDismiss = action
        isPresented = false
    }

    /// `onDismiss` của `.sheet` — mọi đường đóng đều đi qua đây. Đang ở trang kiểm tra nguồn ⇒ giao lượt cho hub (thu nhỏ)
    /// như nút ‹ — không trông vào `onDisappear` của màn (1.3.702).
    func didDismiss() {
        if case .sourceCheck(let embedded) = page {
            MinimizedSourceCheckCoordinator.shared.screenDidClose(embedded.kind, screenId: nil)
        }
        onPresentedChange?(false)
        let action = afterDismiss
        afterDismiss = nil
        action?()
    }
}
