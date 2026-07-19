import Foundation
import Combine

public enum ToastType: Sendable {
    case info
    case success
    case error
}

public final class ToastManager: ObservableObject {
    public static let shared = ToastManager()
    
    @Published public var showingToast = false
    @Published public var toastMessage = ""
    @Published public var toastType: ToastType = .info
    
    private var currentTask: Task<Void, Never>?
    
    private init() {}
    
    public func show(message: String, type: ToastType = .info) {
        currentTask?.cancel()
        
        currentTask = Task { @MainActor in
            self.toastMessage = message
            self.toastType = type
            self.showingToast = true
            
            // Auto hide after 3 seconds
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    self.showingToast = false
                }
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }
}

import SwiftUI

public struct GlobalToastModifier: ViewModifier {
    @ObservedObject private var toastManager = ToastManager.shared
    
    public func body(content: Content) -> some View {
        ZStack {
            content
            
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
                .zIndex(1000)
            }
        }
    }
}

extension View {
    public func globalToast() -> some View {
        self.modifier(GlobalToastModifier())
    }
}
