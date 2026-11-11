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

    /// Tên nguồn cho nút dịch / Cài đặt dịch: tên tiện ích (bản cài rồi catalog) ⇒ tên nguồn lưu trong `Book`.
    static func sourceName(launch: BookContentLaunch, book: Book?) -> String {
        ExtensionLibraryRepository.shared.catalogExtension(packageId: launch.extensionPackageId)?.name
            ?? book?.sourceName ?? ""
    }

    /// Màn Dịch cho chữ Trung gốc của một khối (1.3.837) — phồn→giản theo truyện, như lớp dịch.
    static func definitionRequest(for sentence: String, bookId: String) -> ComicDefinitionSheet.Request {
        ComicDefinitionSheet.Request(
            sentence: sentence,
            bookId: bookId,
            convertsTraditional: TranslationConfigStore.shared.convertsTraditionalToSimplified(bookId: bookId)
        )
    }
}
