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
}
