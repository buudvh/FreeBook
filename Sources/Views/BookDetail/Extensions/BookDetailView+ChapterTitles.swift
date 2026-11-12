import Foundation

/// Tên chương của mục lục tab Chi tiết (đã lưu, online, bảng SwiftData cũ) — qua `ChineseTextPipeline` (1.3.846), cùng
/// luật với sheet mục lục Reader (`BackgroundPagingWorker`) và màn đọc truyện tranh (`ComicChapterTitleTranslator`):
/// phồn → giản là bước riêng chạy **cả khi tắt dịch**; bật dịch ⇒ bản lưu `title_trans` (đã qua bước chuyển, còn chữ Hán
/// thì dịch tiếp) hoặc dịch sống. Tách khỏi `BookDetailView.swift` (file legacy, không được dài thêm).
///
/// Cấu hình đọc **một lần** mỗi lượt vẽ của trang (`tocTitleOptions`, truyền xuống `BookDetailTOCView.titleText`);
/// từng hàng chỉ gọi các hàm `static` dưới đây — không tra `TranslationConfigStore` theo từng hàng.
extension BookDetailView {
    /// Cờ chữ của mục lục: dịch theo công tắc của trang (`isTranslationEnabled`), phồn → giản ba cấp Truyện ⇒ Nguồn ⇒ Tất
    /// cả. Đọc `TranslationDisplayRevision` ⇒ trang vẽ lại (mục lục đổi chữ) khi popup dịch đổi phồn → giản mà công tắc
    /// dịch giữ nguyên.
    internal var tocTitleOptions: ChineseTextPipeline.Options {
        _ = TranslationDisplayRevision.shared.value
        return ChineseTextPipeline.Options(
            converts: TranslationConfigStore.shared.convertsTraditionalToSimplified(
                bookId: actualBookId, packageId: extensionPackageId
            ),
            translates: isTranslationEnabled,
            dictionaryBookId: actualBookId
        )
    }

    /// Mục lục đã lưu: tắt dịch ⇒ tên đã chuyển; có bản lưu ⇒ dùng nó (còn chữ Hán thì dịch tiếp — chuyển lại không đổi
    /// gì nếu bản lưu đã chuyển); không có ⇒ dịch sống tên đã chuyển.
    static func tocTitle(for chap: StoredChapterSnapshot, _ options: ChineseTextPipeline.Options) -> String {
        guard options.translates, let trans = chap.titleTrans, !trans.isEmpty else {
            return ChineseTextPipeline.chapterTitle(chap.title, options)
        }
        return ChineseTextPipeline.chapterTitle(trans, options)
    }

    /// Bảng SwiftData `Chapter` (chỉ khi `ChapterStoreConfiguration.enableSwiftDataTOCWrite`): bản lưu dùng nguyên văn.
    static func tocTitle(for chap: Chapter, _ options: ChineseTextPipeline.Options) -> String {
        ChineseTextPipeline.chapterTitle(chap.title, storedTranslation: chap.titleTrans, options)
    }
}
