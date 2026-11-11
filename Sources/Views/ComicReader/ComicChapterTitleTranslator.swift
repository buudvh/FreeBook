import Foundation

/// Dịch tên chương cho màn đọc comic (thanh trên + mục lục) — **ngoài main**, cùng luật với mục lục tab Chi tiết
/// (`BookDetailView.displayTitle(for:)`) và sheet mục lục Reader (`BackgroundPagingWorker`):
/// - có bản lưu `titleTrans` ⇒ dùng nó (còn chữ Hán thì dịch tiếp), **kể cả khi bật phồn→giản**: phồn→giản chỉ là bước
///   chuyển trước khi dịch, bản lưu đã qua bước đó (`ChapterTitleRetranslator`, 1.3.845);
/// - không có ⇒ dịch sống nếu tên có chữ Hán (chuyển phồn→giản trước nếu truyện bật — ba cấp truyện ⇒ nguồn ⇒ Tất cả).
///
/// Chỉ gọi khi đang bật dịch; tắt dịch thì màn đọc hiện tên gốc, không cần dịch.
enum ComicChapterTitleTranslator {
    /// Bản chụp một dòng mục lục đi qua `Task.detached`.
    private struct Item: Sendable {
        let index: Int
        let title: String
        let titleTrans: String?
    }

    /// Tên đã dịch theo `index` chương. `nil` khi task gọi bị huỷ (lượt dịch mới thay thế).
    static func translatedTitles(for chapters: [ComicChapterEntry], bookId: String, packageId: String) async -> [Int: String]? {
        let items = chapters.map { Item(index: $0.index, title: $0.title, titleTrans: $0.titleTrans) }
        let convertsTraditional = TranslationConfigStore.shared.convertsTraditionalToSimplified(bookId: bookId, packageId: packageId)
        let worker = Task.detached(priority: .userInitiated) { () -> [Int: String]? in
            var titles: [Int: String] = [:]
            titles.reserveCapacity(items.count)
            for (offset, item) in items.enumerated() {
                if offset % 100 == 0, Task.isCancelled { return nil }
                titles[item.index] = ComicChapterTitleTranslator.displayTitle(
                    title: item.title,
                    titleTrans: item.titleTrans,
                    bookId: bookId,
                    convertsTraditional: convertsTraditional
                )
            }
            return Task.isCancelled ? nil : titles
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func displayTitle(title: String, titleTrans: String?, bookId: String, convertsTraditional: Bool) -> String {
        if let trans = titleTrans?.trimmingCharacters(in: .whitespacesAndNewlines), !trans.isEmpty {
            return TranslateUtils.containsChinese(trans)
                ? TranslateUtils.translateChapterTitle(trans, bookId: bookId, shouldConvertTraditionalToSimplified: convertsTraditional)
                : trans
        }
        guard TranslateUtils.containsChinese(title) else { return title }
        return TranslateUtils.translateChapterTitle(
            title,
            bookId: bookId,
            shouldConvertTraditionalToSimplified: convertsTraditional
        )
    }
}
