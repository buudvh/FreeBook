import Foundation

/// Tên chương cho màn đọc comic (thanh trên + mục lục) — **ngoài main**, qua `ChineseTextPipeline`, cùng luật với mục lục
/// tab Chi tiết (`BookDetailView.displayTitle(for:)`) và sheet mục lục Reader (`BackgroundPagingWorker`):
/// - phồn → giản (ba cấp truyện ⇒ nguồn ⇒ Tất cả) là bước riêng, chạy **cả khi tắt dịch** (1.3.846) ⇒ `Titles.converted`;
/// - bật dịch: có bản lưu `titleTrans` ⇒ dùng nó (còn chữ Hán thì dịch tiếp) — bản lưu đã qua bước chuyển
///   (`ChapterTitleRetranslator`, 1.3.845); không có ⇒ dịch sống tên đã chuyển ⇒ `Titles.translated`.
///
/// Gọi khi bật dịch **hoặc** phồn → giản; cả hai tắt thì màn đọc hiện tên gốc.
enum ComicChapterTitleTranslator {
    /// Kết quả một lượt, theo `index` chương.
    struct Titles: Sendable {
        /// Tên đã dịch — chỉ khi bật dịch.
        var translated: [Int: String] = [:]
        /// Tên đã chuyển phồn → giản — chỉ khi bật phồn → giản.
        var converted: [Int: String] = [:]
    }

    /// Bản chụp một dòng mục lục đi qua `Task.detached`.
    private struct Item: Sendable {
        let index: Int
        let title: String
        let titleTrans: String?
    }

    /// Tên theo `index` chương cho cờ `options`. `nil` khi task gọi bị huỷ (lượt dịch mới thay thế).
    static func displayTitles(for chapters: [ComicChapterEntry], options: ChineseTextPipeline.Options) async -> Titles? {
        let items = chapters.map { Item(index: $0.index, title: $0.title, titleTrans: $0.titleTrans) }
        let worker = Task.detached(priority: .userInitiated) { () -> Titles? in
            var titles = Titles()
            for (offset, item) in items.enumerated() {
                if offset % 100 == 0, Task.isCancelled { return nil }
                if options.converts {
                    titles.converted[item.index] = ChineseTextPipeline.convert(item.title, converts: true)
                }
                if options.translates {
                    titles.translated[item.index] = ComicChapterTitleTranslator.translatedTitle(
                        title: item.title, titleTrans: item.titleTrans, options: options
                    )
                }
            }
            return Task.isCancelled ? nil : titles
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Bản lưu (còn chữ Hán thì dịch tiếp; chuyển lại không đổi gì nếu đã chuyển) ⇒ dịch sống tên đã chuyển.
    private static func translatedTitle(title: String, titleTrans: String?, options: ChineseTextPipeline.Options) -> String {
        if let trans = titleTrans?.trimmingCharacters(in: .whitespacesAndNewlines), !trans.isEmpty {
            return ChineseTextPipeline.chapterTitle(trans, options)
        }
        return ChineseTextPipeline.chapterTitle(title, options)
    }
}
