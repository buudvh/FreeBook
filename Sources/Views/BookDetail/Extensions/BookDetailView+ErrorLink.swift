import SwiftUI

extension BookDetailView {
    /// Gán chữ lỗi chi tiết **cùng** link "Mở link lỗi" — mọi chỗ gán `detailErrorMessage` đi qua đây để dòng URL xám
    /// không bao giờ đứng dưới một câu lỗi khác. `sourceError` = lỗi tải từ nguồn (truyền ngay trong `catch`) ⇒ resolve
    /// link, dự phòng URL chi tiết; `nil` (xoá lỗi, lỗi lưu DB, chưa cài tiện ích) ⇒ không có nút.
    internal func setDetailError(_ message: String, sourceError: Error? = nil) {
        detailErrorMessage = message
        detailErrorLink = sourceError.flatMap {
            SourceErrorLink.resolve(from: $0, fallback: initialDetailUrl, host: resolvedHost)
        }
    }

    /// Như `setDetailError` cho mục lục. `failedPageURL` = URL trang mục lục đang tải lúc lỗi (vòng tải nhiều trang biết
    /// được), dự phòng trước URL chi tiết.
    internal func setTOCError(_ message: String, sourceError: Error? = nil, failedPageURL: String? = nil) {
        tocErrorMessage = message
        tocErrorLink = sourceError.flatMap {
            SourceErrorLink.resolve(from: $0, fallbacks: [failedPageURL, initialDetailUrl], host: resolvedHost)
        }
    }
}
