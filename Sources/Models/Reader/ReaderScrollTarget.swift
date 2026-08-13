import Foundation



public struct ReaderScrollTarget: Sendable, Equatable {
    public let chapterIndex: Int
    public let paragraphIndex: Int
    public let reason: ReaderScrollReason

    public init(chapterIndex: Int, paragraphIndex: Int = -1, reason: ReaderScrollReason = .userNavigation) {
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.reason = reason
    }
}
