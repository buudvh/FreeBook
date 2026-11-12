import Foundation

/// Tên chương dịch / đã chuyển phồn → giản của màn đọc comic (tách khỏi file chính để giữ dưới giới hạn dòng). Dựng ngoài
/// main bằng `ComicChapterTitleTranslator`, ghi vào `ComicChapterEntry.translatedTitle` / `convertedTitle`.
extension ComicReaderViewModel {
    /// `ComicReaderView` gọi sau khi mục lục nạp xong, mỗi lần công tắc dịch của truyện đổi, và khi cấu hình dịch /
    /// phồn → giản / từ điển đổi. Phồn → giản chạy cả khi tắt dịch (1.3.846) ⇒ tắt dịch vẫn dựng tên đã chuyển; tắt cả
    /// hai ⇒ bỏ tên đã chuyển (hiện tên gốc). Task gọi bị huỷ ⇒ bỏ kết quả.
    func translateChapterTitles(enabled: Bool) async {
        guard !chapters.isEmpty else { return }
        let source = chapters
        let options = ChineseTextPipeline.Options(
            converts: TranslationConfigStore.shared.convertsTraditionalToSimplified(
                bookId: launch.bookId, packageId: launch.extensionPackageId
            ),
            translates: enabled,
            dictionaryBookId: launch.bookId
        )
        var titles = ComicChapterTitleTranslator.Titles()
        if options.converts || options.translates {
            guard let built = await ComicChapterTitleTranslator.displayTitles(for: source, options: options),
                  !Task.isCancelled else { return }
            titles = built
        }
        // Chỉ gán cho dòng còn đúng chương đã dịch (cùng chỉ số + tên gốc + bản lưu `titleTrans`, 1.3.845): một lượt cũ về
        // muộn sau "Dịch lại tên chương" không được đè bản mới.
        let sourceTitles = Dictionary(source.map { ($0.index, ($0.title, $0.titleTrans)) }, uniquingKeysWith: { first, _ in first })
        chapters = chapters.map { entry in
            guard let origin = sourceTitles[entry.index], origin.0 == entry.title, origin.1 == entry.titleTrans else {
                return entry
            }
            var updated = entry
            updated.convertedTitle = titles.converted[entry.index]
            if options.translates, let title = titles.translated[entry.index] { updated.translatedTitle = title }
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
