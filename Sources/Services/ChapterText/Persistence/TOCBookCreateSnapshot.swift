import Foundation

struct TOCBookCreateSnapshot: Sendable, Equatable {
    let bookId: String
    let title: String
    let author: String
    let coverUrl: String
    let desc: String
    let detailUrl: String
    let sourceName: String
    let sourceUrl: String
    let extensionPackageId: String
    let currentChapterIndex: Int
    let currentChapterPage: Int
    let currentChapterTitle: String
    let isOnShelf: Bool
    let isHistory: Bool
    let host: String?
}
