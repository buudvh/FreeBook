import Foundation

/// Dựng danh sách hàng của mục lục truyện tranh (1.3.843) — hàm thuần, chạy được ngoài main (mục lục dài).
///
/// - Dòng nhóm (`isSection`) **luôn giữ**. Mục lục chia thành từng nhóm theo thứ tự gốc: mỗi dòng nhóm mở một nhóm, các
///   chương trước dòng nhóm đầu tiên là một nhóm không tiêu đề.
/// - Xếp giảm dần ⇒ đảo thứ tự các nhóm **và** các chương trong nhóm; tiêu đề nhóm vẫn đứng ngay trên chương của nó.
/// - Tìm ⇒ trong mỗi nhóm chỉ giữ chương khớp (tên đang hiển thị, tên gốc hoặc tên đã chuyển phồn → giản,
///   `ChapterTitleSearchMatcher`); tiêu đề
///   nhóm tự khớp ⇒ giữ cả nhóm; nhóm không còn gì ⇒ ẩn luôn tiêu đề.
/// - Số thứ tự dựng từ **toàn bộ** mục lục (`ChapterOrdinalNumbering`) ⇒ tìm / đảo vẫn giữ số; dòng nhóm không chiếm số.
///
/// Trước 1.3.843 màn mục lục lọc / đảo / đánh số cả mục lục trong mỗi lượt vẽ, và ẩn dòng nhóm khi tìm hoặc xếp giảm dần.
enum ComicChapterListRows {
    struct Result: Sendable {
        let rows: [ComicChapterEntry]
        /// `nil` = công tắc "Hiện số thứ tự chương" đang tắt.
        let numbering: ChapterOrdinalNumbering?
    }

    /// Một nhóm: dòng nhóm (nếu có) + các chương thường của nó theo thứ tự gốc.
    private struct Group {
        let header: ComicChapterEntry?
        var items: [ComicChapterEntry]
    }

    static func build(
        chapters: [ComicChapterEntry],
        query: String,
        ascending: Bool,
        translated: Bool,
        numbered: Bool
    ) -> Result {
        let numbering = numbered
            ? ChapterOrdinalNumbering(chapters, index: { $0.index }, isSection: { $0.isSection })
            : nil

        var groups: [Group] = []
        for chapter in chapters {
            if chapter.isSection {
                groups.append(Group(header: chapter, items: []))
            } else if groups.isEmpty {
                groups.append(Group(header: nil, items: [chapter]))
            } else {
                groups[groups.count - 1].items.append(chapter)
            }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows: [ComicChapterEntry] = []
        rows.reserveCapacity(chapters.count)
        for group in (ascending ? groups : groups.reversed()) {
            var items = group.items
            if !trimmed.isEmpty {
                let headerMatches = group.header.map { matches(trimmed, $0, translated: translated) } ?? false
                if !headerMatches {
                    items = items.filter { matches(trimmed, $0, translated: translated) }
                }
                guard headerMatches || !items.isEmpty else { continue }
            }
            if let header = group.header {
                rows.append(header)
            }
            rows.append(contentsOf: ascending ? items : items.reversed())
        }
        return Result(rows: rows, numbering: numbering)
    }

    private static func matches(_ query: String, _ chapter: ComicChapterEntry, translated: Bool) -> Bool {
        ChapterTitleSearchMatcher.matches(
            query, anyOf: [chapter.displayTitle(translated: translated), chapter.title, chapter.convertedTitle]
        )
    }
}
