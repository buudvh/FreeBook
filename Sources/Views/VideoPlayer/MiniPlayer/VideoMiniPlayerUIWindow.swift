import UIKit

/// Cửa sổ của trình phát nhỏ (`VideoMiniPlayerWindowManager`): phủ cả màn nhưng chỉ nhận chạm trên chính cửa sổ phim
/// (và cả màn trong lúc nở lại); chạm chỗ khác rơi xuống app. Là lớp phủ (`AppOverlayWindow`) ⇒ không bao giờ được coi là
/// cửa sổ chính của app.
final class VideoMiniPlayerUIWindow: UIWindow, AppOverlayWindow {
    weak var miniPlayerController: VideoMiniPlayerViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event), let controller = miniPlayerController else { return nil }
        return controller.acceptsTouch(on: hit) ? hit : nil
    }
}
