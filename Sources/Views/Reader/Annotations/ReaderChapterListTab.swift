import Foundation

/// Ba tab của sheet mục lục Reader (1.3.1040): Mục lục / Dấu trang / Ghi chú — chip ở đầu panel
/// (`ReaderChapterListView+Annotations`). Reader mở thẳng tab Ghi chú khi chạm dấu đoạn có nhiều ghi chú.
public enum ReaderChapterListTab: String, CaseIterable, Sendable {
    case chapters
    case bookmarks
    case notes
}
