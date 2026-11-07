import SwiftUI
import UIKit

/// Đầu dò UIKit của nút Home nổi: một `UIView` 0×0, không nhận chạm, nằm trong trang (gắn làm `.background`). Mỗi lần
/// được gắn vào cửa sổ, nó đọc vị trí trang (`FloatingHomePlacement.resolve`) ở nhịp main kế tiếp và đọc lại sau 0,35 s
/// (gắn vào cửa sổ giữa nhịp đẩy trang thì quan hệ cha–con của VC có thể chưa xong), đăng ký trang với
/// `FloatingHomeRegistry` theo `role`, rồi báo SwiftUI **chỉ khi** kết quả đổi.
///
/// Rời cửa sổ (trang bị trang khác đè, đổi tab) thì **giữ** kết quả cũ — back về không nháy. Gỡ đăng ký khi SwiftUI gỡ
/// view (`dismantleUIView`: nút "+" có điều kiện biến mất, trang bị bỏ).
struct FloatingHomeProbe: UIViewRepresentable {
    let token: UUID
    let role: FloatingHomeRegistry.Role
    let onResolve: (FloatingHomePlacement?) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.configure(token: token, role: role, onResolve: onResolve)
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.configure(token: token, role: role, onResolve: onResolve)
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: ()) {
        uiView.unregister()
    }

    final class ProbeView: UIView {
        private static let settleDelay: TimeInterval = 0.35

        private var token = UUID()
        private var role: FloatingHomeRegistry.Role = .pageTitle
        private var onResolve: ((FloatingHomePlacement?) -> Void)?
        private var lastPlacement: FloatingHomePlacement?
        private var hasReported = false

        func configure(token: UUID, role: FloatingHomeRegistry.Role, onResolve: @escaping (FloatingHomePlacement?) -> Void) {
            if self.token != token {
                FloatingHomeRegistry.shared.unregister(self.token)
            }
            self.token = token
            self.role = role
            self.onResolve = onResolve
        }

        func unregister() {
            FloatingHomeRegistry.shared.unregister(token)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.resolve() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
                MainActor.assumeIsolated { self?.resolve() }
            }
        }

        private func resolve() {
            guard window != nil else { return }
            guard let resolved = FloatingHomePlacement.resolve(from: self) else {
                report(nil)
                return
            }
            FloatingHomeRegistry.shared.register(token, role: role, host: resolved.page)
            report(resolved.placement)
        }

        private func report(_ placement: FloatingHomePlacement?) {
            guard !hasReported || placement != lastPlacement else { return }
            hasReported = true
            lastPlacement = placement
            onResolve?(placement)
        }
    }
}
