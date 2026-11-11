import Foundation

/// Những gì một ảnh cần để dịch (dịch ảnh, 1.3.826). `ComicReaderView` dựng khi truyện bật dịch (`nil` = tắt) qua
/// `ComicExtensionTextTranslation.imageContext` và truyền xuống từng `ComicPageView` + trình xem phóng to.
///
/// `revision` tăng khi từ điển / cấu hình dịch đổi: là một phần `id` của task trong `ComicTranslationOverlay`, nên các ảnh
/// đang hiện dịch lại (kết quả nhận chữ lấy từ RAM, không nhận chữ lại).
///
/// Bộ dịch là tiện ích dịch ⇒ `extensionRequest` khác `nil`: mỗi ảnh một lô qua tiện ích, khối lỗi lùi QT
/// (`ComicPageTextTranslator`). `extensionRevision` tăng khi cấu hình tiện ích (model, kiểu dịch) đổi mà lượt dịch vẫn bằng
/// nhau ⇒ ảnh dịch lại. Chỉ `Equatable` (`Request` không `Hashable`) — `.task(id:)` chỉ cần vậy.
struct ComicImageTranslationContext: Equatable, Sendable {
    let bookId: String
    let convertsTraditional: Bool
    let revision: Int
    let extensionRequest: ChineseTextExtensionTranslator.Request?
    let extensionRevision: Int
}
