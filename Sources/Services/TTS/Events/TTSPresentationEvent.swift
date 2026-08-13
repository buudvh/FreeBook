import Foundation

public enum TTSPresentationEvent: Sendable, Equatable {
    case showToast(message: String, type: ToastType)
}
