import SwiftUI
import UIKit

/// Đầu dò **neo** của đĩa nghe góc dưới phải (1.3.808): một `UIView` trong suốt, không nhận chạm, gắn làm `.background`
/// của view neo nên có đúng khung của neo. Vào cửa sổ ⇒ đăng ký với `MediaDiscAnchorRegistry` (đọc lại sau 0,35 s như
/// `FloatingHomeProbe`: gắn vào cửa sổ giữa nhịp đẩy trang thì cây VC có thể chưa xong); đổi cỡ ⇒ báo đổi; SwiftUI gỡ
/// view ⇒ gỡ đăng ký. Neo có điều kiện (nút "+" chỉ có khi …, thanh dưới truyện tranh khi hiện chrome) thì cứ gắn trong
/// nhánh `if`: view biến mất là neo biến mất.
struct MediaDiscAnchorProbe: UIViewRepresentable {
    let role: MediaDiscAnchorRegistry.Role

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.role = role
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.updateRole(role)
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: ()) {
        uiView.detach()
    }

    final class ProbeView: UIView {
        private static let settleDelay: TimeInterval = 0.35

        fileprivate(set) var role: MediaDiscAnchorRegistry.Role = .button
        private var isDetached = false
        private var lastSize: CGSize = .zero

        /// Gọi trong lượt cập nhật của SwiftUI ⇒ chỉ ghi lại, đăng ký lại ở nhịp main sau.
        func updateRole(_ newRole: MediaDiscAnchorRegistry.Role) {
            guard newRole != role else { return }
            role = newRole
            scheduleReport()
        }

        func detach() {
            isDetached = true
            MediaDiscAnchorRegistry.shared.unregister(self)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleReport()
            guard window != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
                MainActor.assumeIsolated { self?.report() }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != lastSize else { return }
            lastSize = bounds.size
            MediaDiscAnchorRegistry.shared.noteChange()
        }

        private func scheduleReport() {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.report() }
            }
        }

        private func report() {
            guard !isDetached else { return }
            if window != nil {
                MediaDiscAnchorRegistry.shared.register(self, role: role)
            } else {
                // Rời cửa sổ (trang bị đè, đổi tab) ⇒ không còn là neo; vào lại cửa sổ thì đăng ký lại.
                MediaDiscAnchorRegistry.shared.unregister(self)
            }
        }
    }
}

extension View {
    /// Đánh dấu view này là neo của đĩa nghe góc dưới phải (`MediaDiscAnchorRegistry.Role`).
    func mediaDiscAnchor(_ role: MediaDiscAnchorRegistry.Role) -> some View {
        background {
            MediaDiscAnchorProbe(role: role)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
