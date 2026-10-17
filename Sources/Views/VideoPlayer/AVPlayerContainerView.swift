import SwiftUI
import AVKit
import UIKit

/// Bọc `AVPlayerViewController` (có sẵn nút toàn màn + PiP). Phụ đề là một `UILabel` đặt trong
/// `contentOverlayView` để vẫn hiện khi người dùng bấm toàn màn của AVKit.
///
/// `updateUIViewController` chạy mỗi khi dòng phụ đề đổi (tick 0,5 giây) ⇒ chỉ gán text/ẩn hiện,
/// không dựng lại view.
struct AVPlayerContainerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let subtitleText: String
    var onFullScreenChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFullScreenChange: onFullScreenChange)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        controller.delegate = context.coordinator
        if let overlay = controller.contentOverlayView {
            context.coordinator.installSubtitleLabel(in: overlay)
        }
        context.coordinator.updateSubtitle(subtitleText)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        context.coordinator.onFullScreenChange = onFullScreenChange
        context.coordinator.updateSubtitle(subtitleText)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.delegate = nil
        controller.player = nil
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onFullScreenChange: (Bool) -> Void
        private var subtitleContainer: UIView?
        private var subtitleLabel: UILabel?
        private var currentText = ""

        init(onFullScreenChange: @escaping (Bool) -> Void) {
            self.onFullScreenChange = onFullScreenChange
        }

        func installSubtitleLabel(in overlay: UIView) {
            guard subtitleContainer == nil else { return }
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            container.layer.cornerRadius = 6
            container.isUserInteractionEnabled = false
            container.isHidden = true

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .white
            label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)

            container.addSubview(label)
            overlay.addSubview(container)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                container.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                container.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -16),
                container.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 16),
                container.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -16)
            ])
            subtitleContainer = container
            subtitleLabel = label
        }

        func updateSubtitle(_ text: String) {
            guard text != currentText else { return }
            currentText = text
            subtitleLabel?.text = text
            subtitleContainer?.isHidden = text.isEmpty
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            onFullScreenChange(true)
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                // Người dùng vuốt dở rồi thả (transition bị huỷ) ⇒ vẫn đang toàn màn.
                guard !context.isCancelled else { return }
                self?.onFullScreenChange(false)
            }
        }
    }
}
