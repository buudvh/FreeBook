import Foundation

/// Tên truyện / tên chương ở đầu trang, màn đang tải, màn lỗi và sheet mục lục của Reader (1.3.853).
///
/// - Bản QT (`translateMetaIfNeeded`, `translateChapterTitleIfNeeded`): phồn → giản chạy cả khi tắt dịch, dịch theo
///   ba cấp (`ChineseTextPipeline`, 1.3.846) — cũng là chữ hiện tạm khi bộ dịch là tiện ích.
/// - Bộ dịch là **tiện ích dịch**: `titleTranslations` (`ReaderTitleTranslationStore`) dịch như tên chương trong chương —
///   `title_trans` khi dịch sang tiếng Việt, không thì tiện ích, lỗi ⇒ QT. Cấu hình đẩy vào store **ngoài** `body`
///   (`syncTitleTranslations`, gọi từ `.task(id: titleTranslationKey)` + khi mục lục online đổi).
extension ReaderView {
    /// Tên truyện / chữ meta: phồn → giản chạy cả khi tắt dịch, dịch theo ba cấp (1.3.846, `ChineseTextPipeline`).
    internal func translateMetaIfNeeded(_ text: String) -> String {
        ChineseTextPipeline.meta(text, readerTitleOptions)
    }

    /// Tên chương: phồn → giản chạy cả khi tắt dịch, rồi dịch nếu bật (1.3.846, `ChineseTextPipeline`).
    internal func translateChapterTitleIfNeeded(_ text: String) -> String {
        ChineseTextPipeline.chapterTitle(text, readerTitleOptions)
    }

    /// Tên chương `index` cho đầu trang / màn đang tải / màn lỗi khi chương chưa dựng: bản tiện ích (hoặc `title_trans`)
    /// nếu đã có, không thì QT của `rawTitle`.
    internal func chapterHeaderTitle(at index: Int, rawTitle: String) -> String {
        titleTranslations.title(at: index) ?? translateChapterTitleIfNeeded(rawTitle)
    }

    internal var readerTitleOptions: ChineseTextPipeline.Options {
        ChineseTextPipeline.Options(
            converts: shouldConvertTraditionalToSimplified, translates: isTranslationEnabled, dictionaryBookId: bookId
        )
    }

    /// Khoá dựng lại lượt dịch tiện ích của tên: đổi dịch / phồn → giản / bộ dịch (`TranslationDisplayRevision` tăng cả khi
    /// đổi bộ dịch), truyện vừa lên kệ (tên gốc đọc từ `ChapterStore` thay vì mục lục online).
    internal var titleTranslationKey: String {
        let packageId = localBook?.extensionPackageId ?? extensionPackageId
        return "\(TranslationDisplayRevision.shared.value)|\(isTranslationEnabled)|\(shouldConvertTraditionalToSimplified)"
            + "|\(localBook != nil)|\(packageId)"
    }

    /// Đẩy cấu hình hiện tại vào `titleTranslations` — chỉ gọi ngoài `body`.
    internal func syncTitleTranslations() {
        let packageId = localBook?.extensionPackageId ?? extensionPackageId
        let options = readerTitleOptions
        let readsStoredTOC = localBook != nil && !ChapterStoreConfiguration.enableSwiftDataTOCWrite
        titleTranslations.update(
            bookId: bookId,
            options: options,
            chapterRequest: ChineseTextExtensionTranslator.request(
                bookId: bookId, packageId: packageId, options: options, source: .tableOfContent
            ),
            bookRequest: ChineseTextExtensionTranslator.request(
                bookId: bookId, packageId: packageId, options: options, source: .detail
            ),
            readsStoredTOC: readsStoredTOC,
            onlineTitles: readsStoredTOC ? [] : currentOnlineChapters.map(\.name)
        )
    }
}
