import SwiftUI

/// Matcher thuần cho tìm kiếm sách trong Kệ sách & Lịch sử.
/// Khớp query với 1 trong 4 trường: tên gốc, tên đã dịch, tác giả, tác giả đã phiên âm.
/// Không phụ thuộc trạng thái toggle dịch — các cột `titleTrans`/`authorTrans` được
/// backfill lúc mở app bởi `BookTitleTranslationMigrator`.
enum ShelfBookSearchMatcher {
    static func matches(
        query: String,
        title: String,
        titleTrans: String,
        author: String,
        authorTrans: String
    ) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        return title.localizedCaseInsensitiveContains(q)
            || titleTrans.localizedCaseInsensitiveContains(q)
            || author.localizedCaseInsensitiveContains(q)
            || authorTrans.localizedCaseInsensitiveContains(q)
    }
}
