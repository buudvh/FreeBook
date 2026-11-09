import SwiftData
import SwiftUI

/// Lối vào **duy nhất** từ View để phát một playlist (trang chi tiết playlist: Phát tất cả / Phát ngẫu nhiên / chạm một
/// mục). `PlaylistPlaybackCoordinator` dựng hàng đợi + mở mục đầu; phần trình bày màn nằm ở đây (tầng Services không
/// trình bày UI):
/// - Nhạc: coordinator mở album của mục trong `AudioPlaybackSession` ⇒ trình bày màn nghe ở trang Đĩa
///   (`AudioPlayerPresenter.reopen`).
/// - Phim: coordinator trả request + lượt mở ⇒ `VideoWatchPresenter.present(playlistStart:)` (màn xem đang mở thì đóng
///   trước rồi mở màn mới; model phát luôn dù tắt "Tự phát khi mở phim").
@MainActor
enum PlaylistPlaybackLauncher {
    /// `shuffled`: `false` / `true` của hai nút phát; `nil` = chạm một mục (nhạc giữ xáo đang dùng, phim theo thứ tự).
    static func play(_ playlist: Playlist, startingAt itemId: UUID?, shuffled: Bool?, modelContainer: ModelContainer) {
        let coordinator = PlaylistPlaybackCoordinator.shared
        switch playlist.kind {
        case .audio:
            guard coordinator.startAudio(playlist, startingAt: itemId, shuffled: shuffled, modelContainer: modelContainer) else {
                showNothingToPlay(playlist)
                return
            }
            AudioPlayerPresenter.reopen(at: .disc)
        case .video:
            guard let start = coordinator.startVideo(
                playlist,
                startingAt: itemId,
                shuffled: shuffled ?? false,
                modelContainer: modelContainer
            ) else {
                showNothingToPlay(playlist)
                return
            }
            VideoWatchPresenter.present(start.request, modelContainer: modelContainer, playlistStart: start.start)
        }
    }

    private static func showNothingToPlay(_ playlist: Playlist) {
        ToastManager.shared.show(message: "Playlist chưa có \(playlist.kind.itemNoun) nào để phát", type: .info)
    }
}
