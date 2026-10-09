import Foundation

struct BookMetadataSnapshot: Sendable, Equatable {
    let bookId: String
    let title: String
    let author: String
    let coverUrl: String
    let desc: String
    let detailUrl: String
    let sourceName: String
    let sourceUrl: String
    let extensionPackageId: String
    let host: String?
    let chapters: [ChapterMetadataSnapshot]
}
