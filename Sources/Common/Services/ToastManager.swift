import Foundation
import Combine

public final class ToastManager: ObservableObject {
    public static let shared = ToastManager()
    
    @Published public var showingToast = false
    @Published public var toastMessage = ""
    
    private var currentTask: Task<Void, Never>?
    
    private init() {}
    
    public func show(message: String) {
        currentTask?.cancel()
        
        currentTask = Task { @MainActor in
            self.toastMessage = message
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
