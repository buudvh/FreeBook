import Observation
import UIKit

/// Lựa chọn hiện tại của bộ lọc NSFW riêng tab Kệ Sách (`ShelfNsfwFilter`) — **không lưu đĩa** (người dùng chốt
/// 2026-11-07: *"Tắt app, tắt màn hình, về home mở lên lại sẽ về không hiển thị nfsw"*):
/// - mỗi lần mở app bắt đầu ở `.hide`;
/// - app **vào nền** (khoá màn hình, vuốt về màn hình chính) ⇒ về `.hide`;
/// - bấm nút Home trong app (nút Home nổi, nút "Về Khám phá" của màn xem phim) ⇒ về `.hide` (`resetToHidden`).
///
/// Singleton thay vì `@State` của `ShelfView`: tab Kệ bị dựng lại (`MainTabView.tabResetTokens`) khi đổi tab từ trang con —
/// lựa chọn phải sống qua lần dựng lại đó trong lúc app còn mở. `ShelfView` đọc `mode` trong `body` (Observation) nên đổi
/// ở ngăn kéo là danh sách vẽ lại ngay.
@MainActor
@Observable
final class ShelfNsfwFilterState {
    static let shared = ShelfNsfwFilterState()

    private(set) var mode: ShelfNsfwFilter = .hide

    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?

    private init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                ShelfNsfwFilterState.shared.resetToHidden(reason: "rời app")
            }
        }
    }

    func select(_ mode: ShelfNsfwFilter) {
        guard self.mode != mode else { return }
        AppLogger.shared.log("📚 [ShelfNsfw] Bộ lọc NSFW của Kệ ⇒ \(mode.title)")
        self.mode = mode
    }

    func resetToHidden(reason: String) {
        guard mode != .hide else { return }
        AppLogger.shared.log("📚 [ShelfNsfw] \(reason) ⇒ bộ lọc NSFW của Kệ về \"\(ShelfNsfwFilter.hide.title)\"")
        mode = .hide
    }
}
