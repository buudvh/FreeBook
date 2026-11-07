import SwiftUI

/// Lối **rời màn xem** (`VideoWatchExit`) mà phần dưới khung phim yêu cầu — tách khỏi `VideoPlayerScreen.swift` để file gốc
/// dưới giới hạn dòng. Việc tiếp theo (chuyển tab, mở trang) luôn chạy **sau khi** màn đã đóng (`leave(then:)` →
/// `pendingExitAction` ở `onDisappear`).
extension VideoPlayerScreen {
    /// - Home: thu nhỏ phim (phim 18+ thì `prepareGoHome` đã dừng hẳn) rồi, khi màn đã đóng, về trang gốc tab Khám phá.
    /// - Đổi nguồn xong: đóng hẳn.
    /// - Thể loại / Xem thêm: xem `openCategory(_:from:)`.
    func handleExit(_ exit: VideoWatchExit) {
        guard let watch else { return }
        switch exit {
        case .home:
            watch.prepareGoHome()
            leave(stopPlayback: false) {
                MainTabNavigationEvents.shared.send(.showDiscoveryRoot)
            }
        case .close:
            leave(stopPlayback: true)
        case .openCategory(let category):
            openCategory(category, from: watch)
        }
    }

    /// Thể loại / "Xem thêm ›" lúc màn **đang phát phim của nó** (không nhúng trang): co khung phim vào cửa sổ nhỏ như nút
    /// "Cửa sổ nhỏ" của thanh trên (đang ngang / toàn màn dọc thì xoay về trước), đóng màn rồi mới mở trang danh sách —
    /// mở sớm hơn thì `performDismiss` (đóng trang đè lên màn trước) đóng luôn trang. Trang lúc đó không còn
    /// `VideoWatchModel` ⇒ chọn phim trong trang mở màn xem mới theo lối thường; chạm cửa sổ nhỏ để mở lại màn xem.
    ///
    /// Màn đang hiện bìa (phim khác chạy nền) hoặc phim nhúng trang (không vào cửa sổ nhỏ được) ⇒ giữ kiểu cũ: trang đè lên
    /// màn xem, chọn phim thì đổi tại chỗ.
    private func openCategory(_ category: CategoryResult, from watch: VideoWatchModel) {
        guard !isLeaving else { return }
        guard watchOwnsSession, session.embedContent == nil, !controller.minimizeDrag.isCommitted else {
            VideoWatchPagePresenter.openCategory(category, model: watch)
            return
        }
        // Chụp giá trị thường, không giữ `watch`: trang mở khi màn (và model) đã đi.
        let packageId = watch.request.packageId
        let sourceName = watch.request.sourceName
        let container = watch.modelContainer
        AppLogger.shared.log("🎬 [VideoWatch] Bấm '\(category.title)' ⇒ phim vào cửa sổ nhỏ, đóng màn xem rồi mở trang")
        minimizeToMiniPlayer {
            VideoWatchPagePresenter.openCategory(
                category,
                packageId: packageId,
                sourceName: sourceName,
                modelContainer: container
            )
        }
    }
}
