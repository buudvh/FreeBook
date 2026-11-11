import Foundation

/// Truyện tranh đang bật dịch hay không — **đúng cách trang Chi tiết tính** (`BookDetailView`: `TranslationConfigStore` +
/// gợi ý "nguồn tiếng Trung" từ bản ghi tiện ích), để nút dịch ở Chi tiết và ở màn đọc luôn khớp: truyện này > nguồn >
/// nguồn tự khai tiếng Trung > toàn cục. Quyết định cả tên chương lẫn dịch ảnh (1.3.833).
///
/// Tách khỏi `ComicReaderView` (1.3.834) để file đó còn chỗ dưới giới hạn 400 dòng.
@MainActor
enum ComicTranslationStatus {
    static func isEnabled(for launch: BookContentLaunch) -> Bool {
        TranslationConfigStore.shared.isTranslationEnabled(
            bookId: launch.bookId,
            packageId: launch.extensionPackageId,
            isChineseSourceHint: chineseSourceHint(packageId: launch.extensionPackageId)
        )
    }

    /// Như `BookDetailView.ext?.isChineseSource`: tra bản cài rồi catalog; không thấy ⇒ `nil` (dò `plugin.json`).
    static func chineseSourceHint(packageId: String) -> Bool? {
        ExtensionLibraryRepository.shared.catalogExtension(packageId: packageId)?.isChineseSource
    }
}
