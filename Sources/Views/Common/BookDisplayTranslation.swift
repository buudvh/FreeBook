import Foundation

/// Chữ hiển thị của **truyện đã lưu** (có `bookId`): tên, tác giả, mô tả, tên chương "Đang đọc"… ở Kệ sách, Lịch sử, Bộ
/// sưu tập, Tìm trên kệ, sheet nhấn giữ, sheet chọn truyện, thông báo, tải / xuất, đầu trang Reader / truyện tranh.
///
/// Đi qua `ChineseTextPipeline` (1.3.846): phồn → giản chạy **cả khi tắt dịch**, dịch theo **ba cấp** của popup dịch
/// (Truyện này ⇒ Nguồn này ⇒ Tất cả) — trước đây chỉ theo công tắc Tất cả (`@AppStorage("isTranslationEnabled")`).
///
/// Danh sách dài: đầu `body` của mỗi hàng gọi `listOptions(bookId:packageId:)` **một lần** rồi truyền `Options` xuống
/// các hàm chữ. Hàm đó đọc `TranslationDisplayRevision.shared.value` (hàng vẽ lại khi popup dịch lưu ở bất kỳ cấp nào)
/// và dùng chung **một** `TranslationConfigSnapshot` cho mọi hàng tới lần đổi cấu hình kế tiếp — không hàng nào tự đọc
/// các từ điển cấu hình trong `UserDefaults`.
///
/// Một nguồn cho cả `BookListItemView` (hàng danh sách) và `ShelfBookGridCardView` (thẻ lưới) — đổi luật ở đây là đổi
/// cả hai kiểu hiển thị, không để hai bản chép lệch nhau.
enum BookDisplayTranslation {
    typealias Options = ChineseTextPipeline.Options

    // MARK: - Cấu hình

    /// Cấu hình của một truyện cho hàng / thẻ trong `body`: ghi nhận phụ thuộc vào `TranslationDisplayRevision` và dùng
    /// bản chụp chung (`sharedSnapshot()`).
    @MainActor
    static func listOptions(bookId: String, packageId: String?) -> Options {
        ChineseTextPipeline.options(bookId: bookId, packageId: packageId, in: sharedSnapshot())
    }

    @MainActor
    static func listOptions(for book: Book) -> Options {
        listOptions(bookId: book.bookId, packageId: book.extensionPackageId)
    }

    /// Màn của một truyện đã tự giữ cờ dịch ba cấp (Chi tiết, đầu trang truyện tranh…): ghép cờ đó với phồn → giản của
    /// truyện lấy từ bản chụp chung — đọc `TranslationDisplayRevision` nên màn vẽ lại khi phồn → giản đổi ở popup dịch.
    @MainActor
    static func screenOptions(bookId: String, packageId: String?, translates: Bool) -> Options {
        Options(
            converts: sharedSnapshot().convertsTraditional(bookId: bookId, packageId: packageId),
            translates: translates,
            dictionaryBookId: bookId.isEmpty ? nil : bookId
        )
    }

    /// Một truyện ở sheet / toast / thông báo (không phải danh sách dài): chụp cấu hình mới mỗi lần gọi, gọi được ngoài
    /// main actor. Không ghi nhận phụ thuộc vào `TranslationDisplayRevision`.
    static func options(bookId: String, packageId: String?) -> Options {
        ChineseTextPipeline.options(bookId: bookId, packageId: packageId)
    }

    static func options(for book: Book) -> Options {
        options(bookId: book.bookId, packageId: book.extensionPackageId)
    }

    /// Bản chụp cấu hình dùng chung cho mọi hàng, chụp lại khi `TranslationDisplayRevision` tăng. Đọc `value` ở đây
    /// nên View gọi trong `body` tự vẽ lại theo popup dịch.
    @MainActor
    static func sharedSnapshot() -> TranslationConfigSnapshot {
        let revision = TranslationDisplayRevision.shared.value
        if let cached = cachedSnapshot, cached.revision == revision { return cached.snapshot }
        let snapshot = TranslationConfigStore.shared.snapshot()
        cachedSnapshot = CachedSnapshot(revision: revision, snapshot: snapshot)
        return snapshot
    }

    // MARK: - Chữ

    /// Tên truyện: chuyển / dịch rồi viết hoa chữ đầu mỗi từ — đúng thứ tự `BookListItemView` vẫn làm.
    static func title(_ title: String, _ options: Options) -> String {
        DisplayTextFormatter.titleCase(ChineseTextPipeline.meta(title, options))
    }

    /// Mô tả, tên mục… (`translateMeta`).
    static func text(_ text: String, _ options: Options) -> String {
        ChineseTextPipeline.meta(text, options)
    }

    /// Tác giả: chuyển rồi phiên âm Hán Việt — **chỉ** khi có chữ Hán (phiên âm tách lại từng từ, tên Latin sẽ bị giãn
    /// dấu câu). Không viết hoa: chỗ gọi tự `titleCase` như trước.
    static func author(_ author: String, _ options: Options) -> String {
        guard TranslateUtils.containsChinese(author) else { return author }
        return ChineseTextPipeline.author(author, options)
    }

    /// Tên chương ngoài mục lục ("Đang đọc: …", tên chương trong thông báo chương mới).
    static func chapterTitle(_ title: String, _ options: Options) -> String {
        ChineseTextPipeline.chapterTitle(title, options)
    }

    // MARK: - Bản chụp dùng chung

    private struct CachedSnapshot {
        let revision: Int
        let snapshot: TranslationConfigSnapshot
    }

    @MainActor private static var cachedSnapshot: CachedSnapshot? = nil
}
