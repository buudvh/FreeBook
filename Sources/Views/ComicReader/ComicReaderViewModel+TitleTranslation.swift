import Foundation

/// Tên chương dịch của màn đọc comic (tách khỏi file chính để giữ dưới giới hạn dòng). Dịch ngoài main bằng
/// `ComicChapterTitleTranslator`, ghi kết quả vào `ComicChapterEntry.translatedTitle`.
extension ComicReaderViewModel {
    /// `ComicReaderView` gọi sau khi mục lục nạp xong và mỗi lần công tắc dịch của truyện bật lại. Tắt dịch ⇒ không
    /// làm gì (`displayTitle(translated: false)` luôn là tên gốc). Task gọi bị huỷ ⇒ bỏ kết quả.
    func translateChapterTitles(enabled: Bool) async {
        guard enabled, !chapters.isEmpty else { return }
        let source = chapters
        guard let titles = await ComicChapterTitleTranslator.translatedTitles(for: source, bookId: launch.bookId),
              !Task.isCancelled else { return }
        // Chỉ gán cho dòng còn đúng chương đã dịch (cùng chỉ số + tên gốc).
        let sourceTitles = Dictionary(source.map { ($0.index, $0.title) }, uniquingKeysWith: { first, _ in first })
        chapters = chapters.map { entry in
            guard sourceTitles[entry.index] == entry.title, let title = titles[entry.index] else { return entry }
            var updated = entry
            updated.translatedTitle = title
            return updated
        }
    }

    /// "Dịch lại tên chương" (1.3.844) vừa ghi `title_trans` mới vào `ChapterStore` ⇒ nạp lại `titleTrans` cho mục lục đang
    /// mở (giữ mọi thứ khác) và bỏ `translatedTitle` cũ; `ComicReaderView` gọi `translateChapterTitles` ngay sau đó. Mục lục
    /// online (truyện chưa lưu) không có gì để nạp.
    func reloadStoredTitleTranslations() async {
        guard let stored = try? await ChapterStore.shared.fetchOrderedTOC(bookId: launch.bookId), !stored.isEmpty else { return }
        let titleTransByIndex = Dictionary(stored.map { ($0.index, $0.titleTrans) }, uniquingKeysWith: { first, _ in first })
        chapters = chapters.map { entry in
            guard let titleTrans = titleTransByIndex[entry.index] else { return entry }
            return ComicChapterEntry(
                index: entry.index,
                title: entry.title,
                titleTrans: titleTrans,
                url: entry.url,
                host: entry.host,
                isSection: entry.isSection
            )
        }
    }
}
