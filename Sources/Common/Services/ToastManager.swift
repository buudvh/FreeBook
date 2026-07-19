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
