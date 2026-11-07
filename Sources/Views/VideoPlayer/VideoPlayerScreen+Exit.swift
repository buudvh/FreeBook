import SwiftUI

/// Lối **rời màn xem** (`VideoWatchExit`) mà phần dưới khung phim yêu cầu, và lời xin **thu vào hub** của
/// `VideoLeaveToHubCoordinator` (tắt NSFW lúc phát phim 18+, rời app) — tách khỏi `VideoPlayerScreen.swift` để file gốc dưới giới
/// hạn dòng. Việc tiếp theo (chuyển tab, mở trang) luôn chạy **sau khi** màn đã đóng (`leave(then:)` → `pendingExitAction`
/// ở `onDisappear`).
extension VideoPlayerScreen {
    /// - Home: thu nhỏ phim vào hub (phim 18+ cũng phát tiếp, tắt tiếng theo cài đặt) rồi, khi màn đã đóng, về trang gốc tab
    ///   Khám phá.
    /// - Đổi nguồn xong: đóng hẳn.
    /// - Thể loại / Xem thêm: xem `openCategory(_:from:)`.
    func handleExit(_ exit: VideoWatchExit) {
        guard let watch else { return }
        switch exit {
        case .home:
            guard !isLeaving else { return }
            // Rời màn TRƯỚC rồi mới áp luật: `prepareGoHome` tắt NSFW ⇒ guard NSFW của phiên xin thu phim vào hub ngay trong
            // lượt ghi. Màn đã `isLeaving` nên bỏ qua lời xin đó — không rời hai lần, không nuốt lượt chuyển Khám phá.
            leave(stopPlayback: false) {
                MainTabNavigationEvents.shared.send(.showDiscoveryRoot)
            }
            watch.prepareGoHome()
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

    // MARK: - Thu vào hub theo yêu cầu của dịch vụ

    /// Gọi ở `onAppear`; `onDisappear` gỡ (khoá = `controller`, cùng khoá với `attachScreen`).
    func registerHubCollapse() {
        VideoLeaveToHubCoordinator.shared.register(controller) { reason, then in
            collapseToHub(for: reason, then: then)
        }
    }

    /// Chỉ màn **đang sở hữu phiên** và chưa rời mới thu (màn hiện bìa không gắn phiên — phim chạy nền không thuộc nó).
    /// Trình duyệt "Mở link lỗi" / "Trình duyệt" đang che màn ⇒ bỏ qua: đóng màn lúc đó kéo theo đóng trình duyệt, mà
    /// `onDisappear` vẫn tưởng bị che nên không gỡ màn khỏi phiên (hub mất dòng Video).
    /// - Tắt NSFW ⇒ y như nút ⌄ (dọc thì khung phim bay vào hub, ngang / toàn màn thì đóng), không nhận `then`.
    /// - Rời app ⇒ đóng **không hiệu ứng** (ở nền, completion của animation có thể không bao giờ chạy; hiệu ứng bay đang
    ///   dở cũng bị vượt — completion của nó gọi `leave` lần nữa là no-op), nhận `then` (về Khám phá sau khi màn đã đóng);
    ///   trang đè lên màn (nếu có) tự đóng nhờ `performDismiss`. Không dừng phim.
    private func collapseToHub(for reason: VideoLeaveToHubCoordinator.Reason, then: (() -> Void)?) -> Bool {
        guard !isLeaving, watchOwnsSession else { return false }
        guard controller.openingErrorLink == nil, openingDetailErrorLink == nil, openingDetailPage == nil else {
            AppLogger.shared.log("⚠️ [VideoPlayer] Xin thu vào hub (\(reason.logLabel)) lúc trình duyệt đang che màn ⇒ bỏ qua")
            return false
        }
        switch reason {
        case .nsfwTurnedOff:
            guard !controller.minimizeDrag.isCommitted else { return false }
            AppLogger.shared.log("🔞 [VideoPlayer] Thu màn xem vào hub (\(reason.logLabel)), phim phát tiếp")
            minimizeToHub()
            return false
        case .appBackground:
            AppLogger.shared.log("🎬 [VideoPlayer] Rời app ⇒ đóng màn xem không hiệu ứng, phim vào hub, phát tiếp")
            leave(stopPlayback: false, animated: false, then: then)
            // `onDisappear` có thể bị hoãn tới lúc app quay lại ⇒ gỡ màn khỏi phiên ngay (hub có dòng Video, mở lại được).
            // `onDisappear` gỡ lại là no-op.
            session.detachScreen(controller)
            return true
        }
    }
}
