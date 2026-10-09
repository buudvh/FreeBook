import SwiftUI
import UIKit
import Combine

/// Ảnh bìa tròn của widget TTS, xoay bằng Core Animation (render server chạy) thay cho `TimelineView` của SwiftUI,
/// nên body SwiftUI của widget không còn bị đánh giá lại theo từng frame.
/// Góc quay lấy từ `CoverRotationState` (sống lâu hơn view) nên đổi peeking/expanded hay đổi sách vẫn giữ đúng góc.
/// Khi không phát hoặc widget không thật sự hiển thị, animation bị gỡ (góc giữ bằng transform tĩnh) để render server không vẽ lại.
struct TTSRotatingCoverView: UIViewRepresentable {
    let image: UIImage?
    let size: CGFloat
    let rotationState: CoverRotationState
    let isRotating: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        // Không nhận chạm để Button/gesture phía trên (SwiftUI và UIKit) xử lý như khi còn là Image.
        container.isUserInteractionEnabled = false
        container.backgroundColor = .clear
        container.clipsToBounds = true
        context.coordinator.build(in: container)
        context.coordinator.update(container: container, image: image, size: size)
        context.coordinator.attach(rotationState: rotationState, isRotating: isRotating)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(container: uiView, image: image, size: size)
        context.coordinator.setRotating(isRotating)
    }

    /// Giữ các view UIKit và animation xoay của một ảnh bìa.
    @MainActor
    final class Coordinator {
        private static let animationKey = "ttsCoverRotation"

        private let rotatingView = UIView()
        private let fallbackGradient = CAGradientLayer()
        private let fallbackIconView = UIImageView()
        private let imageView = UIImageView()
        private weak var rotationState: CoverRotationState?
        private var isRotating = false
        private var appliedImage: UIImage?
        private var didApplyImage = false
        private var appliedSize: CGFloat = -1
        private var cancellables = Set<AnyCancellable>()

        func build(in container: UIView) {
            rotatingView.isUserInteractionEnabled = false
            rotatingView.backgroundColor = .clear

            // Ảnh dự phòng giống bản SwiftUI cũ: gradient xám → đen + biểu tượng sách trắng.
            fallbackGradient.colors = [
                UIColor.systemGray.withAlphaComponent(0.5).cgColor,
                UIColor.black.withAlphaComponent(0.8).cgColor
            ]
            fallbackGradient.startPoint = CGPoint(x: 0, y: 0)
            fallbackGradient.endPoint = CGPoint(x: 1, y: 1)
            rotatingView.layer.addSublayer(fallbackGradient)

            fallbackIconView.contentMode = .center
            fallbackIconView.tintColor = UIColor.white.withAlphaComponent(0.88)
            rotatingView.addSubview(fallbackIconView)

            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            rotatingView.addSubview(imageView)

            container.addSubview(rotatingView)
        }

        func update(container: UIView, image: UIImage?, size: CGFloat) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }

            if size != appliedSize {
                appliedSize = size
                let bounds = CGRect(x: 0, y: 0, width: size, height: size)
                container.layer.cornerRadius = size / 2
                // Đặt bounds/center (không đặt frame) để không phụ thuộc transform xoay đang chạy.
                rotatingView.bounds = bounds
                rotatingView.center = CGPoint(x: size / 2, y: size / 2)
                fallbackGradient.frame = bounds
                fallbackIconView.frame = bounds
                imageView.frame = bounds
                fallbackIconView.image = UIImage(
                    systemName: "book.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.36, weight: .semibold)
                )
            }

            if !didApplyImage || image !== appliedImage {
                didApplyImage = true
                appliedImage = image
                imageView.image = image
                imageView.isHidden = image == nil
                fallbackGradient.isHidden = image != nil
                fallbackIconView.isHidden = image != nil
            }
        }

        func attach(rotationState: CoverRotationState, isRotating: Bool) {
            self.rotationState = rotationState
            self.isRotating = isRotating

            // Đổi sách → `CoverRotationState.resetAngle` tăng thế hệ; chạy lại animation từ góc 0 của model.
            rotationState.$resetGeneration
                .dropFirst()
                .sink { [weak self] _ in
                    self?.restartFromModelAngle()
                }
                .store(in: &cancellables)

            // Phòng trường hợp hệ thống gỡ animation khỏi layer khi app xuống nền.
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.restoreAnimationIfNeeded()
                }
                .store(in: &cancellables)

            restartFromModelAngle()
        }

        func setRotating(_ rotating: Bool) {
            guard rotating != isRotating else {
                restoreAnimationIfNeeded()
                return
            }
            isRotating = rotating
            if rotating {
                // Tiếp tục từ góc của model (đồng hồ thực khi đang phát), khớp hành vi TimelineView cũ.
                restartFromModelAngle()
            } else {
                freeze()
            }
        }

        private func restoreAnimationIfNeeded() {
            guard isRotating, rotatingView.layer.animation(forKey: Self.animationKey) == nil else { return }
            restartFromModelAngle()
        }

        /// Đặt góc hiện tại của `CoverRotationState` làm transform tĩnh, rồi gắn animation xoay nếu đang được xoay.
        private func restartFromModelAngle() {
            let layer = rotatingView.layer
            layer.removeAnimation(forKey: Self.animationKey)
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0

            let startRadians = (rotationState?.currentAngle() ?? 0) * Double.pi / 180.0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DMakeRotation(CGFloat(startRadians), 0, 0, 1)
            CATransaction.commit()
            guard isRotating else { return }

            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = startRadians
            animation.byValue = 2.0 * Double.pi
            animation.duration = 360.0 / CoverRotationState.rotationSpeed
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            // Giữ trần 30 fps như TimelineView cũ (minimumInterval 1/30); mặc định CA chạy theo tần số màn hình.
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
            layer.add(animation, forKey: Self.animationKey)
        }

        /// Dừng xoay: giữ góc đang hiển thị bằng transform tĩnh rồi **gỡ** animation. Không dùng mẫu `speed = 0`:
        /// nó đóng băng mọi animation trong cây layer con (kể cả animation chuyển cảnh của UIKit/SwiftUI).
        private func freeze() {
            let layer = rotatingView.layer
            guard layer.animation(forKey: Self.animationKey) != nil else { return }
            let shownRadians = (layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? NSNumber)?.doubleValue ?? 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DMakeRotation(CGFloat(shownRadians), 0, 0, 1)
            layer.removeAnimation(forKey: Self.animationKey)
            CATransaction.commit()
        }
    }
}
