import SwiftUI

extension BookDetailView {
    /// Chữ của trang Chi tiết theo **truyện đang mở** (1.3.846): tên, tác giả, mô tả, thể loại, tiêu đề thẻ đề xuất /
    /// bình luận, tiêu đề ngăn kéo `…`. Phồn → giản theo Truyện ⇒ Nguồn ⇒ Tất cả, chạy **cả khi tắt dịch**; dịch theo
    /// `isTranslationEnabled` (đã là ba cấp, cùng giá trị mục lục đang dùng).
    ///
    /// Đọc `TranslationDisplayRevision` (qua `BookDisplayTranslation.screenOptions`) ⇒ trang vẽ lại khi phồn → giản đổi ở
    /// popup dịch — `@State isTranslationEnabled` chỉ đổi theo công tắc dịch.
    var metaTextOptions: ChineseTextPipeline.Options {
        BookDisplayTranslation.screenOptions(
            bookId: actualBookId,
            packageId: extensionPackageId,
            translates: isTranslationEnabled
        )
    }

    /// Tên truyện đề xuất, bình luận / trả lời: cùng cấu hình với truyện đang mở nhưng chỉ dùng từ điển chung (như
    /// trước — chữ của truyện khác / của người đọc, không phải của truyện này).
    var relatedTextOptions: ChineseTextPipeline.Options {
        var options = metaTextOptions
        options.dictionaryBookId = nil
        return options
    }

    // MARK: - Bộ dịch tiện ích (1.3.853)

    /// Chữ của phần đầu tab Chi tiết (tên, giới thiệu, thể loại), tiêu đề thẻ, tiêu đề ngăn kéo `…`: QT hoặc tiện ích dịch
    /// (`source: .detail`).
    var detailText: BookDetailText {
        BookDetailText(options: metaTextOptions, store: textStores.detail)
    }

    /// Đề xuất, bình luận / trả lời: cùng store `.detail`, bản QT chỉ dùng từ điển chung.
    var relatedText: BookDetailText {
        BookDetailText(options: relatedTextOptions, store: textStores.detail)
    }

    /// Tên chương của tab Mục lục: QT (`tocTitleOptions`, ưu tiên `title_trans`) hoặc tiện ích dịch (`source:
    /// .tableOfContent`).
    var tocText: BookDetailText {
        BookDetailText(options: tocTitleOptions, store: textStores.toc)
    }

    /// Đọc `TranslationDisplayRevision` trong `body` ⇒ đổi cấu hình dịch / phồn → giản / bộ dịch ở bất kỳ cấp nào là
    /// `syncTextStores()` chạy lại.
    var textSyncKey: BookDetailText.SyncKey {
        BookDetailText.SyncKey(
            revision: TranslationDisplayRevision.shared.value,
            translates: isTranslationEnabled,
            bookId: actualBookId
        )
    }

    /// Dựng lại lượt dịch của hai store (gọi ngoài `body`: `.onChange(of: textSyncKey, initial: true)`). Bộ dịch QT hoặc
    /// tắt dịch ⇒ `request` `nil`, store chỉ trả bản QT; giống lượt cũ ⇒ store không làm gì.
    func syncTextStores() {
        let detailOptions = metaTextOptions
        textStores.detail.update(
            options: detailOptions,
            request: ChineseTextExtensionTranslator.request(
                bookId: actualBookId, packageId: extensionPackageId, options: detailOptions, source: .detail
            )
        )
        let tocOptions = tocTitleOptions
        textStores.toc.update(
            options: tocOptions,
            request: ChineseTextExtensionTranslator.request(
                bookId: actualBookId, packageId: extensionPackageId, options: tocOptions, source: .tableOfContent
            )
        )
    }
}
