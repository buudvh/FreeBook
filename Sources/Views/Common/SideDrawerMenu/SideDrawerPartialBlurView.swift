import SwiftUI
import UIKit

/// Lớp làm nhoè **một phần** cho nền ngăn kéo menu ("kính đục vừa", 1.3.633).
///
/// Material của SwiftUI (`.ultraThinMaterial`…) chỉ có một mức nhoè, và mức đó mạnh: nền Kệ gần như toàn đen bị nhoè
/// thành một mảng xám đều, nhìn như nền đặc (người dùng chê ở 1.3.622–630). UIKit cũng không cho chỉnh bán kính nhoè,
/// nên dùng cách quen thuộc: một `UIViewPropertyAnimator` chuyển `effect` từ `nil` sang `UIBlurEffect` rồi **dừng giữa
/// chừng** ở `intensity` — bìa và chữ phía sau còn nhận ra được, chỉ mềm đi.
///
/// Animator bị hệ thống dừng khi app vào nền hoặc view rời cửa sổ ⇒ dựng lại khi view vào cửa sổ và khi app trở lại
/// foreground. Trước khi thả animator luôn `stopAnimation(true)`: thả một animator đang tạm dừng là crash.
struct SideDrawerPartialBlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    /// 0…1 — phần của hiệu ứng nhoè đầy đủ được áp.
    let intensity: CGFloat

    func makeUIView(context: Context) -> EffectView {
        EffectView(blurEffect: UIBlurEffect(style: style), intensity: intensity)
    }

    func updateUIView(_ uiView: EffectView, context: Context) {
        uiView.update(blurEffect: UIBlurEffect(style: style), intensity: intensity)
    }

    final class EffectView: UIVisualEffectView {
        private var blurEffect: UIBlurEffect
        private var intensity: CGFloat
        private var animator: UIViewPropertyAnimator?
        private var foregroundObserver: NSObjectProtocol?

        init(blurEffect: UIBlurEffect, intensity: CGFloat) {
            self.blurEffect = blurEffect
            self.intensity = intensity
            super.init(effect: nil)
            isUserInteractionEnabled = false
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.rebuildAnimator()
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) không dùng")
        }

        deinit {
            animator?.stopAnimation(true)
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
        }

        func update(blurEffect: UIBlurEffect, intensity: CGFloat) {
            guard intensity != self.intensity || blurEffect !== self.blurEffect else { return }
            // `UIBlurEffect` mới mỗi lần SwiftUI cập nhật ⇒ chỉ dựng lại khi cường độ đổi thật.
            let intensityChanged = intensity != self.intensity
            self.blurEffect = blurEffect
            self.intensity = intensity
            if intensityChanged {
                rebuildAnimator()
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                rebuildAnimator()
            }
        }

        private func rebuildAnimator() {
            animator?.stopAnimation(true)
            effect = nil
            let target = blurEffect
            let newAnimator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
                self?.effect = target
            }
            newAnimator.pausesOnCompletion = true
            newAnimator.fractionComplete = max(0, min(1, intensity))
            animator = newAnimator
        }
    }
}
