import SwiftUI

struct ReaderRouterRoute: Identifiable {
    let bookId: String
    let extensionPackageId: String
    let chapterIndex: Int
    let onlineChapters: [ChapterResult]
    let bookTitle: String?
    let bookAuthor: String?
    let bookCoverUrl: String?
    let bookDesc: String?
    let bookDetailUrl: String?
    let bookSourceName: String?
    let initialParagraphIndex: Int?

    var id: String { "\(bookId)_\(chapterIndex)" }
}

final class ReaderRouter: ObservableObject {
    @Published var route: ReaderRouterRoute?
}
