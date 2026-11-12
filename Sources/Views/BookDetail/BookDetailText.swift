import Foundation

/// Chữ của trang Chi tiết (1.3.853): bản **QT** theo `options` (phồn → giản + dịch ba cấp, đúng ngay lượt vẽ đầu) hoặc,
/// khi bộ dịch của truyện (popup dịch, mục BỘ DỊCH) là **tiện ích dịch**, bản tiện ích qua `store`
/// (`ExtensionTextTranslationStore`): chưa có thì hiện bản QT và xin dịch nền — store gom các mẩu **đang hiện** thành lô
/// sau một nhịp ngắn, xong thì trang vẽ lại; tiện ích lỗi ⇒ giữ bản QT (runner đã log `❌ [ExtTranslate]`).
///
/// Trang giữ **hai** store (`Stores`): `.detail` cho tên / giới thiệu / thể loại / tiêu đề thẻ / đề xuất / bình luận + trả
/// lời, `.tableOfContent` cho tab Mục lục. `BookDetailView.syncTextStores()` dựng lại lượt dịch khi cấu hình dịch, phồn →
/// giản, bộ dịch hay truyện đổi (ngoài `body`). Tác giả **không** đi tiện ích — vẫn phiên âm Hán Việt.
@MainActor
struct BookDetailText {
    /// Hai store dịch bằng tiện ích của trang — một `@State` của `BookDetailView` (file legacy, không dài thêm).
    @MainActor
    struct Stores {
        let detail = ExtensionTextTranslationStore()
        let toc = ExtensionTextTranslationStore()
    }

    /// Khoá dựng lại hai store: `TranslationDisplayRevision` (cấu hình dịch / phồn → giản / bộ dịch / từ điển đổi) + cờ dịch
    /// của trang + truyện.
    struct SyncKey: Equatable {
        let revision: Int
        let translates: Bool
        let bookId: String
    }

    /// Cấu hình QT của chỗ hiện (đề xuất / bình luận: chỉ từ điển chung).
    let options: ChineseTextPipeline.Options
    /// `nil` ⇒ chỉ QT (màn xem phim mở `AllCommentsView` / `CommentRowView` bằng init cũ).
    let store: ExtensionTextTranslationStore?

    static func quickOnly(_ options: ChineseTextPipeline.Options) -> BookDetailText {
        BookDetailText(options: options, store: nil)
    }

    /// Tên, giới thiệu, thể loại, tiêu đề thẻ, tên truyện đề xuất, bình luận… (`ChineseTextPipeline.meta` khi QT).
    func meta(_ raw: String) -> String {
        translated(raw, kind: .meta) { ChineseTextPipeline.meta(raw, options) }
    }

    /// Tên chương của tab Mục lục — luật như tên chương trong Reader: bộ dịch ra tiếng Việt và có `title_trans` ⇒ bản
    /// lưu (`quick`, không gọi tiện ích); không thì tiện ích; lỗi / chưa xong ⇒ `quick` (bản QT màn tự dựng).
    func chapterTitle(_ raw: String, storedTranslation: String?, quick: () -> String) -> String {
        if let request = activeRequest, request.targetsVietnamese,
           let stored = storedTranslation, !stored.isEmpty {
            return quick()
        }
        return translated(raw, kind: .chapterTitle, quick: quick)
    }

    /// Bản tiện ích đã có của một tên chương (ô tìm khớp thêm bản này); `nil` khi chưa có / không dùng tiện ích.
    func chapterTranslation(of raw: String) -> String? {
        guard activeRequest != nil else { return nil }
        return store?.translation(of: raw, kind: .chapterTitle)
    }

    // MARK: - Nội bộ

    /// Lượt dịch tiện ích còn hiệu lực — `options.translates` chặn lượt cũ trong một nhịp trước khi store kịp đổi.
    private var activeRequest: ChineseTextExtensionTranslator.Request? {
        guard options.translates else { return nil }
        return store?.request
    }

    private func translated(_ raw: String, kind: ChineseTextExtensionTranslator.Kind, quick: () -> String) -> String {
        guard activeRequest != nil, let store else { return quick() }
        if let hit = store.translation(of: raw, kind: kind) { return hit }
        return store.text(raw, kind: kind, quick: quick())
    }
}
