import Combine
import SwiftUI
import UIKit

/// Lớp nháy đỏ của nút hub nổi khi có tiến trình đang chạy (người dùng chốt 2026-10-22), đặt trong vòng tròn của
/// `FloatingHubButton`, dưới icon.
///
/// ## Một chỗ hằng số cho cả hai nút nháy
/// Màu và nhịp nằm ở đây dưới dạng `static`; `VisibleBrowserReopenButton` (trình duyệt thu nhỏ) đọc lại đúng các
/// hằng này ⇒ hai nút đồng bộ **màu + nhịp** theo cấu trúc. **Pha** không bảo đảm trùng: nút trình duyệt nháy
/// bằng animation SwiftUI, hub bằng Core Animation.
///
/// Dải màu là nội suy tuyến tính `darkRed` (mức 0) → `brightRed` (mức 1). Nút trình duyệt thực tế dao động giữa
/// mức `pulseDimLevel` và mức 1 (không xuống tới 0), nên hub cũng nháy đúng khoảng đó để hai nút cùng màu.
///
/// ## Vì sao Core Animation
/// Animation SwiftUI `repeatForever` hay `TimelineView` đánh giá lại body theo từng frame — `rules.md` cấm ở
/// widget nổi (cùng lý do với `TTSRotatingCoverView`). Ở đây `CABasicAnimation` chạy trên render server, trần
/// 20 fps, và chỉ tồn tại khi đang nháy **và** view còn trong cửa sổ.
///
/// ## Không đổi opacity
/// Chỉ đổi **màu nền** của một layer con. Không đụng `alpha`/`opacity` của hosting view, `widgetContainerView`
/// hay cửa sổ: `FloatingHubUIWindow.hitTest` có guard `alpha > 0.01` trên `widgetContainerView`.
struct FloatingHubPulseView: UIViewRepresentable {
    /// Đỏ sẫm — mức 0 của dải nội suy (alpha luôn 1).
    static let darkRed = (red: 0.42, green: 0.04, blue: 0.04)
    /// Đỏ tươi — mức 1 của dải nội suy, cũng là đỉnh sáng của nhịp nháy.
    static let brightRed = (red: 0.90, green: 0.17, blue: 0.17)
    /// Đáy tối **thật sự** của nhịp nháy trên dải nội suy: nhịp chạy `pulseDimLevel` ↔ 1.
    static let pulseDimLevel = 0.4
    /// Một chiều tối → sáng (giây). Cả chu kỳ đi và về là gấp đôi.
    static let pulseHalfPeriod: TimeInterval = 0.9

    /// Thành phần RGB (0…1) tại `level` trên dải `darkRed` → `brightRed`. Hàm thuần, không dùng làm opacity.
    static func pulseRGB(level: Double) -> (red: Double, green: Double, blue: Double) {
        (
            red: darkRed.red + (brightRed.red - darkRed.red) * level,
            green: darkRed.green + (brightRed.green - darkRed.green) * level,
            blue: darkRed.blue + (brightRed.blue - darkRed.blue) * level
        )
    }

    let isPulsing: Bool

    func makeUIView(context: Context) -> PulseUIView {
        let view = PulseUIView(frame: .zero)
        view.setPulsing(isPulsing)
        return view
    }

    func updateUIView(_ uiView: PulseUIView, context: Context) {
        uiView.setPulsing(isPulsing)
    }

    /// View UIKit giữ layer nháy. `FloatingHubContainerViewController.refreshButton()` gán lại `rootView` ở mọi lần
    /// `ButtonState` đổi ⇒ `setPulsing` bị gọi lặp: chỉ gắn animation khi **chưa có**, chỉ gỡ khi **đang có** — gắn
    /// lại mỗi lần là giật pha.
    final class PulseUIView: UIView {
        private static let animationKey = "floatingHubPulse"

        private let pulseLayer = CALayer()
        private var isPulsing = false
        private var cancellables = Set<AnyCancellable>()

        override init(frame: CGRect) {
            super.init(frame: frame)
            // Không nhận chạm: kéo/chạm do gesture của `widgetContainerView` xử lý.
            isUserInteractionEnabled = false
            backgroundColor = .clear
            // Màu model luôn trong suốt ⇒ gỡ animation là hết đỏ, không để lại màu tĩnh.
            pulseLayer.backgroundColor = UIColor.clear.cgColor
            layer.addSublayer(pulseLayer)

            // Phòng trường hợp hệ thống gỡ animation khỏi layer khi app xuống nền (khuôn `TTSRotatingCoverView`).
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.restoreAnimationIfNeeded()
                }
                .store(in: &cancellables)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pulseLayer.frame = bounds
            // `backgroundColor` của layer tự cắt theo `cornerRadius` ⇒ không cần mask.
            pulseLayer.cornerRadius = min(bounds.width, bounds.height) / 2
            CATransaction.commit()
        }

        /// Rời cửa sổ ⇒ gỡ để render server không vẽ vô ích; quay lại mà vẫn nháy ⇒ gắn lại.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                removeAnimationIfPresent()
            } else {
                restoreAnimationIfNeeded()
            }
        }

        func setPulsing(_ pulsing: Bool) {
            isPulsing = pulsing
            if pulsing {
                restoreAnimationIfNeeded()
            } else {
                removeAnimationIfPresent()
            }
        }

        private func restoreAnimationIfNeeded() {
            guard isPulsing,
                  window != nil,
                  pulseLayer.animation(forKey: Self.animationKey) == nil else { return }

            let halfPeriod = FloatingHubPulseView.pulseHalfPeriod
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = Self.pulseColor(level: FloatingHubPulseView.pulseDimLevel)
            animation.toValue = Self.pulseColor(level: 1)
            animation.duration = halfPeriod
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.isRemovedOnCompletion = false
            // Đổi màu chậm thì 15 fps đã mượt; mặc định CA chạy theo tần số màn hình.
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 15)
            // Neo đầu chu kỳ vào bội số của cả chu kỳ trên đồng hồ chung ⇒ gỡ rồi gắn lại (rời cửa sổ, về
            // foreground) vẫn đúng pha, không giật về đỏ sẫm.
            let fullPeriod = halfPeriod * 2
            let anchor = floor(CACurrentMediaTime() / fullPeriod) * fullPeriod
            animation.beginTime = pulseLayer.convertTime(anchor, from: nil)
            pulseLayer.add(animation, forKey: Self.animationKey)
        }

        private func removeAnimationIfPresent() {
            guard pulseLayer.animation(forKey: Self.animationKey) != nil else { return }
            pulseLayer.removeAnimation(forKey: Self.animationKey)
        }

        private static func pulseColor(level: Double) -> CGColor {
            let rgb = FloatingHubPulseView.pulseRGB(level: level)
            return UIColor(red: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: 1).cgColor
        }
    }
}
