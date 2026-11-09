import SwiftData
import SwiftUI
import UIKit

/// Mở **màn nghe** (`AudioPlayerScreen`) của trình nghe âm thanh (tiện ích loại `audio`):
/// - `present(_:modelContainer:autoplay:)`: lối vào từ item danh sách (Khám phá, Tìm, Thể loại…) — mở album trong
///   `AudioPlaybackSession` rồi trình bày màn nghe bằng UIKit `.overFullScreen` (host trong suốt, màn bên dưới vẫn sống,
///   như `VideoWatchPresenter`).
/// - `install()`: gắn `presentScreenHandler` vào session — mở lại màn nghe gắn với album đang chạy (sheet điều khiển
///   nhanh của đĩa góc dưới, màn khoá). Gọi lặp an toàn (`present`, `openInPlace` và màn nghe lúc hiện đều gọi).
/// - `reopen(at:)`: mở lại nhưng vào thẳng một trang (sheet điều khiển nhanh của đĩa góc dưới).
/// - `openInPlace(_:modelContainer:autoplay:)`: lối của router (`AudioListenRouteView`, màn nằm sẵn trong
///   `fullScreenCover` của chỗ gọi) — chỉ mở album, không trình bày gì.
///
/// Không bao giờ chồng hai màn nghe: màn nghe đang hiện (gắn vào session, kể cả màn trong cover của router) ⇒ chỉ đổi
/// album trong session, màn đang hiện tự vẽ theo.
@MainActor
final class AudioPlayerPresenter {
    static let shared = AudioPlayerPresenter()

    private weak var hostController: UIViewController?
    /// Trang mở vào của lượt trình bày kế tiếp (`reopen(at:)`); `nil` ⇒ trang Đĩa. Dùng một lần.
    private var requestedPage: AudioPlayerPage?
    private static let maxRetryCount = 6

    private init() {}

    /// Gắn handler mở lại màn nghe vào session (rẻ, idempotent).
    static func install() {
        AudioPlaybackSession.shared.presentScreenHandler = { animated, completion in
            AudioPlayerPresenter.shared.presentScreen(animated: animated, retryCount: 0, completion: completion)
        }
    }

    /// Mở album rồi trình bày màn nghe. `autoplay == false` (mở lại mục nghe gần nhất lúc khởi động): nạp tới bài + giây
    /// đã lưu rồi dừng sẵn.
    static func present(
        _ request: AudioListenRequest,
        modelContainer: ModelContainer,
        autoplay: Bool = true,
        animated: Bool = true
    ) {
        openInPlace(request, modelContainer: modelContainer, autoplay: autoplay)
        shared.presentScreen(animated: animated, retryCount: 0, completion: {})
    }

    /// Mở lại màn nghe của album đang chạy ở trang chỉ định (sheet điều khiển nhanh của đĩa góc dưới: khối bìa + tên /
    /// Danh sách / Lời).
    /// Không có album / màn nghe đang hiện ⇒ không làm gì; trang chỉ áp cho đúng lượt trình bày này (xoá ở `completion`).
    static func reopen(at page: AudioPlayerPage) {
        install()
        shared.requestedPage = page
        AudioPlaybackSession.shared.requestScreen {
            AudioPlayerPresenter.shared.requestedPage = nil
        }
    }

    /// Chỉ mở album trong session (màn nghe do chỗ gọi tự dựng — router).
    static func openInPlace(_ request: AudioListenRequest, modelContainer: ModelContainer, autoplay: Bool) {
        install()
        AudioPlaybackSession.shared.open(request, modelContainer: modelContainer, autoplay: autoplay)
    }

    // MARK: - Trình bày

    private var isHostVisible: Bool {
        guard let host = hostController else { return false }
        return host.presentingViewController != nil && !host.isBeingDismissed
    }

    private func presentScreen(animated: Bool, retryCount: Int, completion: @escaping () -> Void) {
        let session = AudioPlaybackSession.shared
        guard session.isActive, !session.isScreenAttached, !isHostVisible else {
            completion()
            return
        }
        guard let top = VideoPlayerPresenter.findTopViewController() else {
            AppLogger.shared.log("❌ [AudioPlayerUI] Không tìm được màn để trình bày màn nghe")
            completion()
            return
        }
        if top.isBeingPresented || top.isBeingDismissed {
            guard retryCount < Self.maxRetryCount else {
                AppLogger.shared.log("❌ [AudioPlayerUI] Trình bày màn nghe thất bại: màn trên cùng đang chuyển cảnh quá lâu")
                completion()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    AudioPlayerPresenter.shared.presentScreen(animated: animated, retryCount: retryCount + 1, completion: completion)
                }
            }
            return
        }

        let host = AudioPlayerHostingController(rootView: AnyView(EmptyView()))
        host.modalPresentationStyle = .overFullScreen
        host.modalPresentationCapturesStatusBarAppearance = true
        // Trong suốt: màn tự vẽ nền, trượt xuống theo tay khi thu nhỏ để lộ màn bên dưới.
        host.view.backgroundColor = .clear
        let page = requestedPage ?? .disc
        requestedPage = nil
        // Trình bày bằng UIKit ⇒ không thừa hưởng `.tint` / `.modelContainer` của `MainTabView`: gắn lại cả hai.
        let screen = AudioPlayerScreen(initialPage: page, onDismiss: { [weak host] animated in
            // Đóng từ VC đã trình bày host: host đang có menu / trình duyệt con thì `host.dismiss` chỉ đóng con.
            (host?.presentingViewController ?? host)?.dismiss(animated: animated)
        })
        .appAccentTint()
        if let container = session.modelContainer {
            host.rootView = AnyView(screen.modelContainer(container))
        } else {
            host.rootView = AnyView(screen)
        }
        hostController = host
        AppLogger.shared.log("🎵 [AudioPlayerUI] Trình bày màn nghe (bookId=\(session.bookId), trang \(page))")
        top.present(host, animated: animated) {
            completion()
        }
    }
}
