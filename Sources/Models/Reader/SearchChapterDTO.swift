import Foundation

@available(iOS 17.0, *)
public struct SearchChapterDTO: Sendable {
    public let index: Int
    public let title: String
    public let url: String
    public let isCached: Bool

    public init(index: Int, title: String, url: String, isCached: Bool) {
        self.index = index
        self.title = title
        self.url = url
        self.isCached = isCached
    }
}
