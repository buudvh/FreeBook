import Foundation

struct ReaderChapterLoadFailure: Equatable {
    let generation: Int
    let targetChapterIndex: Int
    let chapterTitle: String
    let sourceMessage: String
    let source: ReaderNavigationSource
    let paragraphIndex: Int
    let persistProgress: Bool
    let forceRefresh: Bool
    /// Link "Mở link lỗi" của **chương đích** (`targetChapterIndex`, không phải chương đang hiển thị) — resolve trong
    /// `catch` của worker (`ReaderViewModel.chapterErrorLink(at:error:)`); `nil` ⇒ không có nút.
    var errorLink: SourceErrorLink? = nil
}
