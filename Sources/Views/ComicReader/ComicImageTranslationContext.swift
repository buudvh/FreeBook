import Foundation

/// Những gì một ảnh cần để dịch (dịch ảnh, 1.3.826). `ComicReaderView` dựng khi công tắc Dịch ảnh bật (`nil` = tắt) và
/// truyền xuống từng `ComicPageView`.
///
/// `revision` tăng khi từ điển / cấu hình dịch đổi: là một phần `id` của task trong `ComicTranslationOverlay`, nên các ảnh
/// đang hiện dịch lại (kết quả nhận chữ lấy từ RAM, không nhận chữ lại).
struct ComicImageTranslationContext: Hashable, Sendable {
    let bookId: String
    let convertsTraditional: Bool
    let revision: Int
}
