import Foundation

public enum DownloadPresentationEvent: Sendable, Equatable {
    case showToast(message: String, type: ToastType)
}
