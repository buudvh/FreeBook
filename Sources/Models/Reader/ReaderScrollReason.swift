import Foundation

public enum ReaderScrollReason: Sendable, Equatable {
    case userNavigation
    case ttsAuto
    case initialRestore
}
