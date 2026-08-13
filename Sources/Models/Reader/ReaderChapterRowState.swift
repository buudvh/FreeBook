import Foundation
import Observation

@MainActor
@Observable
public final class ReaderChapterRowState: Identifiable {
    public let id: Int
    public let index: Int
    public var title: String
    public var url: String
    public var isCached: Bool
    public var isPlaceholder: Bool

    public init(id: Int, index: Int, title: String = "", url: String = "", isCached: Bool = false, isPlaceholder: Bool = true) {
        self.id = id
        self.index = index
        self.title = title
        self.url = url
        self.isCached = isCached
        self.isPlaceholder = isPlaceholder
    }
}
