import SwiftUI
import UIKit

/// Presents the floating TTS widget in its own UIWindow at `.alert` level, above
/// every app presentation (reader fullScreenCover, bypass browser pageSheet,
/// sheets...). The window only captures touches inside the widget's current
/// frame; every other touch falls through to the application below.
@MainActor
public final class TTSFloatingWidgetWindowManager {
    public static let shared = TTSFloatingWidgetWindowManager()

    private var window: FloatingWidgetUIWindow?
    private var hostingController: UIHostingController<TTSFloatingWidgetView>?
    private var widgetFrame: CGRect = .zero

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    public func presentWidget() {
        if let window, !window.isHidden {
            return
        }
        guard let windowScene = Self.activeWindowScene else {
            AppLogger.shared.log("⚠️ [TTSFloatingWidget] Không tìm thấy UIWindowScene để tạo window widget.")
            return
        }

        let hosting = UIHostingController(rootView: TTSFloatingWidgetView())
        hosting.view.backgroundColor = .clear

        let win = FloatingWidgetUIWindow(windowScene: windowScene)
        win.windowLevel = .alert
        win.backgroundColor = .clear
        win.rootViewController = hosting
        win.frame = windowScene.coordinateSpace.bounds
        win.widgetFrameProvider = { [weak self] in self?.widgetFrame ?? .zero }

        self.hostingController = hosting
        self.window = win
        win.isHidden = false
    }

    public func dismissWidget() {
        window?.isHidden = true
        window = nil
        hostingController = nil
        widgetFrame = .zero
    }

    public func updateWidgetFrame(_ frame: CGRect) {
        widgetFrame = frame
    }

    @objc private func handleDidBecomeActive() {
        // Scene có thể bị tạo lại sau khi app active; nếu window đang treo trên
        // scene cũ thì tạo lại trên scene đang active.
        guard window != nil else { return }
        guard let windowScene = Self.activeWindowScene, window?.windowScene !== windowScene else { return }
        let wasVisible = window?.isHidden == false
        dismissWidget()
        if wasVisible {
            presentWidget()
        }
    }

    private static var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }
}

/// A full-screen transparent window whose hit test returns nil everywhere except
/// inside the floating widget frame, so touches outside the widget pass through
/// to the application window below.
@MainActor
private final class FloatingWidgetUIWindow: UIWindow {
    var widgetFrameProvider: () -> CGRect = { .zero }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard widgetFrameProvider().contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}