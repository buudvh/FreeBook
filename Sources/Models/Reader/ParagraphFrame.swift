import Foundation

public struct ParagraphFrame: Equatable {
    public let bookId: String
    public let chapterIndex: Int
    public let paragraphIndex: Int
    public let minY: CGFloat
    public let maxY: CGFloat

    public init(bookId: String, chapterIndex: Int, paragraphIndex: Int, minY: CGFloat, maxY: CGFloat) {
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.minY = minY
        self.maxY = maxY
    }
}
