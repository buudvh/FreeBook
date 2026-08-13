import Foundation

public struct ChapterRowItem: Identifiable, Sendable, Equatable, Hashable {
    public let id: Int
    public let index: Int

    public init(id: Int, index: Int) {
        self.id = id
        self.index = index
    }
}
