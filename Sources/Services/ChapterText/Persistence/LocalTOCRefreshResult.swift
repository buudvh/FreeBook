import Foundation

public struct LocalTOCRefreshResult: Equatable, Sendable {
    public let totalCount: Int
    public let readerOldIndex: Int
    public let readerNewIndex: Int
    public let ttsOldIndex: Int?
    public let ttsNewIndex: Int?
    public let isTOCUnchanged: Bool
    public let isReaderChapterRemoved: Bool
    public let isTTSChapterRemoved: Bool

    public init(
        totalCount: Int,
        readerOldIndex: Int,
        readerNewIndex: Int,
        ttsOldIndex: Int? = nil,
        ttsNewIndex: Int? = nil,
        isTOCUnchanged: Bool = false,
        isReaderChapterRemoved: Bool = false,
        isTTSChapterRemoved: Bool = false
    ) {
        self.totalCount = totalCount
        self.readerOldIndex = readerOldIndex
        self.readerNewIndex = readerNewIndex
        self.ttsOldIndex = ttsOldIndex
        self.ttsNewIndex = ttsNewIndex
        self.isTOCUnchanged = isTOCUnchanged
        self.isReaderChapterRemoved = isReaderChapterRemoved
        self.isTTSChapterRemoved = isTTSChapterRemoved
    }
}
