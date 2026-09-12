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
    }
    
    public func show(message: String, type: ToastType = .info) {
        // Choke point duy nhất mọi toast đi qua ⇒ ghi vào nhật ký Trung tâm thông báo tại đây.
        NotificationInboxManager.shared.record(message: message, type: type)

        currentTask?.cancel()
        
        self.toastMessage = message
        self.toastType = type
        self.showingToast = true
        ensureWindow()
        
        // Auto hide after 3 seconds
        currentTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    self.showingToast = false
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if !Task.isCancelled && !self.showingToast {
                        self.window?.isHidden = true
                    }
                }
            } catch {
                // Task was cancelled, do nothing
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
    
    @objc private func handleSceneDidActivate(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
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

    private var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }
}

/// Window hiển thị Toast nổi trên tất cả các màn hình, hoàn toàn passthrough touch xuống bên dưới.
@MainActor
final class ToastUIWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Toasts are purely informational HUDs, always pass touch through
        return nil
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.1).opacity(0.92))
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    )
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.25), value: toastManager.showingToast)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

