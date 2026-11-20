import Observation
import UIKit

/// Lựa chọn hiện tại của bộ lọc NSFW tab Kệ Sách (`ShelfNsfwFilter`) — **không lưu đĩa** (người dùng chốt
/// 2026-11-07: *"Tắt app, tắt màn hình, về home mở lên lại sẽ về không hiển thị nfsw"*):
/// - mỗi lần mở app bắt đầu ở `.hide` (công tắc chung cũng tự tắt lúc mở app — `resetNsfwVisibilityOnLaunch`);
/// - app **vào nền** (khoá màn hình, vuốt về màn hình chính) ⇒ về `.hide`;
/// - bấm nút Home trong app (nút Home nổi, nút "Về Khám phá" của màn xem phim) ⇒ về `.hide` (`resetToHidden`).
///
/// **Đồng bộ với công tắc NSFW chung** (`RepositoryFilterPolicy.includeNsfwDefaultsKey`, 1.3.985 — anh Bửu: "đồng bộ tuỳ
/// chọn nsfw của kệ với những chỗ khác (chỉ nsfw / tất cả = bật)"):
/// - Kệ chọn "Tất cả" / "Chỉ NSFW" ⇒ công tắc chung **bật**; "Không hiển thị NSFW" ⇒ **tắt**.
/// - Chỗ khác bật công tắc (Khám phá, Cài đặt, bộ lọc Kho…) ⇒ Kệ đang "Không hiển thị" chuyển sang "Tất cả"; chỗ khác tắt
///   ⇒ Kệ về "Không hiển thị". "Chỉ NSFW" vẫn là lựa chọn riêng của Kệ (công tắc chung chỉ có bật / tắt).
/// - Bấm Home ⇒ tắt **cả hai** ngay.
/// - Rời app (vào nền) ⇒ Kệ về "Không hiển thị" **ngay** (ảnh chụp ở màn chuyển app không lộ), còn công tắc chung chỉ tắt
///   khi **mở lại app** (`willEnterForeground`) — anh Bửu chọn "Tắt khi mở lại app" sau khi review chỉ ra tắt ngay lúc
///   vào nền làm phim NSFW đang xem tắt tiếng + thu vào hub, playlist NSFW dừng sau bài, Reader truyện NSFW bị đóng khi khoá
///   máy. Trong lúc ở nền, đồng bộ từ công tắc chung tạm ngưng (kẻo Kệ đang ẩn bị kéo lại "Tất cả").
/// Nghe thay đổi của công tắc qua `UserDefaults.didChangeNotification` (mọi chỗ ghi đều là `@AppStorage` / `UserDefaults`).
///
/// Singleton thay vì `@State` của `ShelfView`: tab Kệ bị dựng lại (`MainTabView.tabResetTokens`) khi đổi tab từ trang con —
/// lựa chọn phải sống qua lần dựng lại đó trong lúc app còn mở. `ShelfView` đọc `mode` trong `body` (Observation) nên đổi
/// ở ngăn kéo là danh sách vẽ lại ngay. `MainTabView` chạm `shared` lúc hiện để luật rời app / mở lại chạy cả khi chưa
/// mở tab Kệ.
@MainActor
@Observable
final class ShelfNsfwFilterState {
    static let shared = ShelfNsfwFilterState()

    private(set) var mode: ShelfNsfwFilter

    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    /// Đã rời app ⇒ lúc mở lại tắt công tắc chung; trong lúc chờ, không kéo Kệ theo công tắc chung.
    @ObservationIgnored private var turnsGlobalOffOnReturn = false

    private init() {
        mode = RepositoryFilterPolicy.includesNsfwPreference ? .all : .hide
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                ShelfNsfwFilterState.shared.handleDidEnterBackground()
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                ShelfNsfwFilterState.shared.handleWillEnterForeground()
            }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                ShelfNsfwFilterState.shared.syncFromGlobalSwitch()
            }
        }
    }

    func select(_ mode: ShelfNsfwFilter) {
        guard self.mode != mode else { return }
        AppLogger.shared.log("📚 [ShelfNsfw] Bộ lọc NSFW của Kệ ⇒ \(mode.title)")
        self.mode = mode
        setGlobalSwitch(mode != .hide, reason: "Kệ chọn \"\(mode.title)\"")
    }

    /// Về "Không hiển thị NSFW" **và** tắt công tắc NSFW chung (nút Home).
    func resetToHidden(reason: String) {
        setGlobalSwitch(false, reason: reason)
        hideShelf(reason: reason)
    }

    // MARK: - Rời app / mở lại

    private func handleDidEnterBackground() {
        turnsGlobalOffOnReturn = true
        hideShelf(reason: "rời app")
    }

    private func handleWillEnterForeground() {
        guard turnsGlobalOffOnReturn else { return }
        turnsGlobalOffOnReturn = false
        setGlobalSwitch(false, reason: "mở lại app")
        hideShelf(reason: "mở lại app")
    }

    private func hideShelf(reason: String) {
        guard mode != .hide else { return }
        AppLogger.shared.log("📚 [ShelfNsfw] \(reason) ⇒ bộ lọc NSFW của Kệ về \"\(ShelfNsfwFilter.hide.title)\"")
        mode = .hide
    }

    // MARK: - Đồng bộ công tắc chung

    private func setGlobalSwitch(_ isOn: Bool, reason: String) {
        guard RepositoryFilterPolicy.includesNsfwPreference != isOn else { return }
        AppLogger.shared.log("📚 [ShelfNsfw] \(reason) ⇒ công tắc NSFW chung \(isOn ? "bật" : "tắt")")
        UserDefaults.standard.set(isOn, forKey: RepositoryFilterPolicy.includeNsfwDefaultsKey)
    }

    /// Công tắc chung đổi ở chỗ khác ⇒ kéo Kệ theo (chỉ khi lệch: tắt mà Kệ đang hiện NSFW, bật mà Kệ đang ẩn).
    private func syncFromGlobalSwitch() {
        guard !turnsGlobalOffOnReturn else { return }
        let isOn = RepositoryFilterPolicy.includesNsfwPreference
        if !isOn, mode != .hide {
            AppLogger.shared.log("📚 [ShelfNsfw] Công tắc NSFW chung tắt ⇒ Kệ về \"\(ShelfNsfwFilter.hide.title)\"")
            mode = .hide
        } else if isOn, mode == .hide {
            AppLogger.shared.log("📚 [ShelfNsfw] Công tắc NSFW chung bật ⇒ Kệ \"\(ShelfNsfwFilter.all.title)\"")
            mode = .all
        }
    }
}
