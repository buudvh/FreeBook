import Foundation
import Combine
import SwiftUI
import UIKit

public enum ToastType: Sendable, Equatable {
    case info
    case success
    case error
}

@MainActor
public final class ToastManager: ObservableObject {
    public static let shared = ToastManager()
    
    @Published public var showingToast = false
    @Published public var toastMessage = ""
    @Published public var toastType: ToastType = .info
    /// Hành động khi bấm toast đang hiện (1.3.748). `nil` = toast chỉ để đọc, chạm xuyên qua như cũ.
    @Published public private(set) var tapAction: (@MainActor () -> Void)?
    /// Khung viên thuốc theo toạ độ cửa sổ toast — `ToastUIWindow` chỉ nhận chạm trong khung này khi có `tapAction`.
    var tappableFrame: CGRect = .null

    private var currentTask: Task<Void, Never>?
    private var window: ToastUIWindow?
    private var hostingController: UIHostingController<ToastOverlayView>?
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSceneDidActivate),
            name: UIScene.didActivateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSceneDidDisconnect),
            name: UIScene.didDisconnectNotification,
            object: nil
        )
    }
    
    /// `recordsInInbox: false` cho phản hồi tức thời không đáng lưu (vd "Đã sao chép" của thanh bàn phím): không ghi vào
    /// Trung tâm thông báo, không tăng badge chưa đọc.
    ///
    /// `onTap` (1.3.748): toast nhận chạm **trong viên thuốc** (có dấu `›`), bấm ⇒ ẩn ngay rồi chạy hành động. Mục ghi ở
    /// Trung tâm thông báo vẫn chỉ là chữ.
    public func show(
        message: String,
        type: ToastType = .info,
        recordsInInbox: Bool = true,
        onTap: (@MainActor () -> Void)? = nil
    ) {
        // Choke point duy nhất mọi toast đi qua ⇒ ghi vào nhật ký Trung tâm thông báo tại đây.
        if recordsInInbox {
            NotificationInboxManager.shared.record(message: message, type: type)
        }

        currentTask?.cancel()

        self.toastMessage = message
        self.toastType = type
        self.tapAction = onTap
        self.showingToast = true
        ensureWindow()

        // Auto hide after 3 seconds
        currentTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    self.hideAnimated()
                }
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }

    /// Bấm vào viên thuốc của toast có `onTap`.
    func handleTap() {
        guard showingToast, let action = tapAction else { return }
        currentTask?.cancel()
        hideAnimated()
        action()
    }

    /// Ẩn toast; cửa sổ ẩn sau hiệu ứng (0,3 s) nếu không có toast mới chen vào.
    private func hideAnimated() {
        showingToast = false
        tapAction = nil
        currentTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled && !self.showingToast {
                self.window?.isHidden = true
            }
        }
    }
    
    private func ensureWindow() {
        guard let windowScene = activeWindowScene else { return }
        
        if let existingWindow = window {
            if existingWindow.windowScene !== windowScene {
                existingWindow.windowScene = windowScene
            }
            if existingWindow.isHidden {
                existingWindow.isHidden = false
            }
            return
        }
        
        let overlayView = ToastOverlayView(toastManager: self)
        let hosting = UIHostingController(rootView: overlayView)
        hosting.view.backgroundColor = .clear
        
        let win = ToastUIWindow(windowScene: windowScene)
        win.windowLevel = .alert
        win.backgroundColor = .clear
        win.rootViewController = hosting
        
        self.hostingController = hosting
        self.window = win
        win.isHidden = false
    }
    
    /// Chỉ theo scene chứa giao diện chính (`AppMainWindowScene`) — scene của PiP cũng báo `didActivate`.
    @objc private func handleSceneDidActivate(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene,
              AppMainWindowScene.isMainInterface(scene) else { return }
        if window?.windowScene !== scene {
            window?.windowScene = scene
        }
    }

    @objc private func handleDidBecomeActive() {
        guard let scene = activeWindowScene else { return }
        if window?.windowScene !== scene {
            window?.windowScene = scene
        }
    }

    /// Scene đang giữ cửa sổ toast bị ngắt ⇒ đưa về scene chính (toast sau vẫn hiện được).
    @objc private func handleSceneDidDisconnect(_ notification: Notification) {
        guard let window, let scene = notification.object as? UIScene else { return }
        guard window.windowScene == nil || window.windowScene === scene else { return }
        if let target = AppMainWindowScene.current(excluding: scene) {
            window.windowScene = target
        }
    }

    private var activeWindowScene: UIWindowScene? {
        AppMainWindowScene.current()
    }
}

/// Window hiển thị Toast nổi trên tất cả các màn hình, passthrough touch xuống bên dưới.
@MainActor
final class ToastUIWindow: UIWindow, AppOverlayWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Toast chỉ để đọc ⇒ luôn chạm xuyên qua. Toast có `onTap` (1.3.748) chỉ nhận chạm **trong viên thuốc**: cửa sổ ở
        // level `.alert` phủ cả màn, trả `super` cho mọi điểm là nuốt hết chạm của app trong 3 giây.
        let manager = ToastManager.shared
        guard manager.showingToast, manager.tapAction != nil, manager.tappableFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

public struct ToastOverlayView: View {
    @ObservedObject var toastManager: ToastManager
    
    public var body: some View {
        ZStack {
            if toastManager.showingToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        switch toastManager.toastType {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .error:
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                        case .info:
                            EmptyView()
                        }
                        
                        Text(toastManager.toastMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)

                        if toastManager.tapAction != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.1).opacity(0.92))
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    )
                    // Khung cho `ToastUIWindow.hitTest` (cửa sổ phủ cả màn từ gốc toạ độ ⇒ `.global` = toạ độ cửa sổ).
                    // Đo bằng `GeometryReader`: deployment iOS 17, `onGeometryChange` chỉ có từ iOS 18.
                    .background(
                        GeometryReader { proxy in
                            let frame = proxy.frame(in: .global)
                            Color.clear
                                .onAppear { toastManager.tappableFrame = frame }
                                .onChange(of: frame) { _, newFrame in toastManager.tappableFrame = newFrame }
                        }
                    )
                    .contentShape(Capsule())
                    .onTapGesture { toastManager.handleTap() }
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.25), value: toastManager.showingToast)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Chỉ bỏ safe area của màn, **giữ** vùng bàn phím: cửa sổ toast nằm dưới cửa sổ bàn phím, bỏ cả vùng bàn phím thì
        // toast lúc đang gõ (vd "Đã sao chép" của thanh bàn phím) bị bàn phím che mất.
        .ignoresSafeArea(.container)
    }
}

