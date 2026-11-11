import Foundation

/// **Một** đường cho mọi chữ Trung đưa ra màn hình, đọc TTS hay xuất file (1.3.846):
/// 1. **phồn → giản** nếu bật — bước riêng, chạy **cả khi tắt dịch**;
/// 2. **dịch QT** nếu bật;
/// 3. còn không thì trả chữ (đã chuyển).
///
/// Khi phồn → giản bật, "chữ gốc" ở mọi nơi là chữ **đã chuyển**: đoạn gốc của Reader (`ParagraphItem.original`), chữ
/// TTS đọc khi tắt dịch, câu gốc của màn Dịch, tên truyện / tác giả / tên chương khi tắt dịch, chữ xuất TXT…
///
/// Cách dùng: đọc cấu hình **một lần** thành `Options` (cùng luật ba cấp với popup dịch — `options(bookId:…)` cho màn có
/// truyện, `sourceOptions(packageId:…)` cho màn chưa có truyện), rồi truyền vào các hàm chữ. Danh sách dài chụp
/// `TranslationConfigStore.shared.snapshot()` một lần mỗi lượt dựng và truyền vào `in:` — đừng tra từng hàng trong `body`.
///
/// Chương truyện chữ: `normalizeChapter(_:converts:)` chuyển **trước** khi chuẩn hoá ⇒ line ID / range UTF-16 tính trên
/// chữ đã chuyển. Reader và TTS **phải** cùng đi hàm này thì toạ độ highlight mới khớp; dòng nhận về đã chuyển ⇒ dịch
/// từng dòng bằng `options.alreadyConverted`.
///
/// Ngoài phạm vi (giữ gọi `TranslateUtils` thẳng): cầu `Qt` của `JSExecutor` (hợp đồng tiện ích), tên nguồn Legado,
/// bộ dịch bằng tiện ích (`TranslationExtensionChapterTranslator` tự lo phồn → giản trước khi gửi).
enum ChineseTextPipeline {
    struct Options: Sendable, Equatable {
        /// Bước 1: phồn → giản.
        var converts: Bool
        /// Bước 2: dịch QT.
        var translates: Bool
        /// Truyện có từ điển / rule riêng (`nil` = chỉ bộ chung).
        var dictionaryBookId: String?

        static let passthrough = Options(converts: false, translates: false, dictionaryBookId: nil)

        /// Cho chữ **đã** qua bước chuyển (dòng của `normalizeChapter`, `title_trans`…): giữ cờ dịch, bỏ bước chuyển để
        /// khỏi chạy ICU lần hai. Kết quả y hệt (chuyển hai lần không đổi gì).
        var alreadyConverted: Options {
            Options(converts: false, translates: translates, dictionaryBookId: dictionaryBookId)
        }
    }

    // MARK: - Cấu hình

    /// Màn có truyện (đã lưu hoặc đang mở): Truyện ⇒ Nguồn ⇒ Tất cả — cùng luật với popup dịch. `isChineseSourceHint`
    /// `nil` ⇒ lấy từ bản ghi tiện ích trong RAM (như Chi tiết), không dò `plugin.json` trên đĩa.
    static func options(
        bookId: String,
        packageId: String?,
        isChineseSourceHint: Bool? = nil,
        in snapshot: TranslationConfigSnapshot? = nil
    ) -> Options {
        let config = snapshot ?? TranslationConfigStore.shared.snapshot()
        let hint = isChineseSourceHint ?? recordChineseHint(packageId)
        return Options(
            converts: config.convertsTraditional(bookId: bookId, packageId: packageId),
            translates: config.isTranslationEnabled(bookId: bookId, packageId: packageId, isChineseSourceHint: hint),
            dictionaryBookId: bookId.isEmpty ? nil : bookId
        )
    }

    /// Màn chưa có truyện (Khám phá, Tìm kiếm, bộ lọc tiện ích, đề xuất…): Nguồn ⇒ Tất cả. `dictionaryBookId` chỉ chọn
    /// từ điển riêng, không tham gia luật bật/tắt.
    static func sourceOptions(
        packageId: String?,
        isChineseSourceHint: Bool? = nil,
        dictionaryBookId: String? = nil,
        in snapshot: TranslationConfigSnapshot? = nil
    ) -> Options {
        let config = snapshot ?? TranslationConfigStore.shared.snapshot()
        let hint = isChineseSourceHint ?? recordChineseHint(packageId)
        return Options(
            converts: config.convertsTraditional(bookId: nil, packageId: packageId),
            translates: config.isTranslationEnabled(bookId: nil, packageId: packageId, isChineseSourceHint: hint),
            dictionaryBookId: dictionaryBookId.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// Gợi ý "nguồn tiếng Trung" từ bản ghi tiện ích đã cài (RAM). Sách nhập từ file ⇒ `nil` (theo Tất cả); nguồn đã gỡ
    /// ⇒ `false` (như Chi tiết: không có `plugin.json` để dò).
    private static func recordChineseHint(_ packageId: String?) -> Bool? {
        guard let packageId, !packageId.isEmpty, !TranslationConfigStore.isLocalPackage(packageId) else { return nil }
        return ExtensionLibraryRepository.snapshot(packageId: packageId)?.isChineseSource ?? false
    }

    // MARK: - Bước 1: phồn → giản

    /// Chuyển phồn → giản khi `converts` và chuỗi có chữ Hán. Chuỗi ngắn (tên, mô tả, dòng) nhớ kết quả — danh sách vẽ lại
    /// liên tục, ICU không rẻ.
    static func convert(_ text: String, converts: Bool) -> String {
        guard converts, !text.isEmpty, TranslateUtils.containsChinese(text) else { return text }
        guard text.utf16.count <= memoMaxLength else {
            return TranslateUtils.textForTranslation(text, shouldConvertTraditionalToSimplified: true)
        }
        let key = text as NSString
        if let hit = conversionMemo.object(forKey: key) { return hit as String }
        let converted = TranslateUtils.textForTranslation(text, shouldConvertTraditionalToSimplified: true)
        conversionMemo.setObject(converted as NSString, forKey: key, cost: converted.utf16.count * 2)
        return converted
    }

    // MARK: - Bước 1 + 2

    /// Tên truyện, mô tả, tag, thể loại, bình luận, tên mục… (`translateMeta`).
    static func meta(_ text: String, _ options: Options) -> String {
        let source = convert(text, converts: options.converts)
        guard options.translates, TranslateUtils.containsChinese(source) else { return source }
        return TranslateUtils.translateMeta(source, bookId: options.dictionaryBookId)
    }

    /// Tác giả: chuyển rồi phiên âm Hán Việt (`translateAuthorHanViet`).
    static func author(_ text: String, _ options: Options) -> String {
        let source = convert(text, converts: options.converts)
        guard options.translates else { return source }
        return TranslateUtils.translateAuthorHanViet(source)
    }

    /// Tên chương dịch sống (`translateChapterTitle`, có bộ rule tên chương).
    static func chapterTitle(_ text: String, _ options: Options) -> String {
        let source = convert(text, converts: options.converts)
        guard options.translates, TranslateUtils.containsChinese(source) else { return source }
        return TranslateUtils.translateChapterTitle(source, bookId: options.dictionaryBookId)
    }

    /// Tên chương ở mục lục / danh sách: đang dịch ⇒ bản lưu `title_trans` (đã qua phồn → giản của truyện,
    /// `ChapterTitleRetranslator`), rỗng ⇒ dịch sống; tắt dịch ⇒ tên đã chuyển. Gọi lúc dựng hàng, không trong `body`.
    static func chapterTitle(_ text: String, storedTranslation: String?, _ options: Options) -> String {
        if options.translates, let stored = storedTranslation, !stored.isEmpty { return stored }
        return chapterTitle(text, options)
    }

    static func chapterTitleWithMapping(_ text: String, _ options: Options) -> TranslatedTextResult {
        let source = convert(text, converts: options.converts)
        guard options.translates, TranslateUtils.containsChinese(source) else {
            return TranslateUtils.untranslatedTextResult(source)
        }
        return TranslateUtils.translateChapterTitleWithMapping(source, bookId: options.dictionaryBookId)
    }

    /// Nội dung (xuất TXT, AI, phụ đề…) — không cần span.
    static func content(_ text: String, _ options: Options) -> String {
        let source = convert(text, converts: options.converts)
        guard options.translates, TranslateUtils.containsChinese(source) else { return source }
        return TranslateUtils.translateContent(source, bookId: options.dictionaryBookId)
    }

    /// Một dòng nội dung có span (Reader, TTS). Span tính trên chữ **đã chuyển** — chữ gốc giữ kèm (`original` của
    /// `ParagraphItem`, `originalText` của `TTSLineEntry`) phải là `convert(text, …)`, tức dòng của `normalizeChapter`.
    static func contentWithMapping(_ text: String, _ options: Options) -> TranslatedTextResult {
        let source = convert(text, converts: options.converts)
        guard options.translates, TranslateUtils.containsChinese(source) else {
            return TranslateUtils.untranslatedTextResult(source)
        }
        return TranslateUtils.translateContentWithMapping(source, bookId: options.dictionaryBookId)
    }

    // MARK: - Chương truyện chữ

    /// Chuẩn hoá chương **sau** bước chuyển (lọc rác chạy trên chữ đã chuyển). Reader và TTS cùng gọi hàm này; chỗ khác
    /// cần dòng như Reader thấy (AI, xuất) cũng vậy. Kho lưu trữ / `ChapterDocument` vẫn giữ chữ thô.
    static func normalizeChapter(_ rawContent: String, converts: Bool) -> NormalizedChapterText {
        ChapterTextNormalizer.normalize(convert(rawContent, converts: converts))
    }

    // MARK: - Memo

    private static let memoMaxLength = 512
    private static let conversionMemo: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 4000
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()
}
