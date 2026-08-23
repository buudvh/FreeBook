import Foundation

/// Gom và trả lại ảnh bìa trong archive. Là nơi duy nhất đọc/ghi entry `covers/<slug>.jpg`,
/// giữ cho hai chiều xuất–khôi phục không lệch nhau.
///
/// Chỉ lấy bìa **không tải lại được**: truyện nhập từ file chỉ có file JPEG trong `covers/`
/// và `coverUrl` rỗng, nên mất backup là mất luôn bìa. Truyện online có `coverUrl` là
/// `http(s)` thì bỏ qua để archive không phình thêm hàng chục MB ảnh tải lại được.
///
/// Không có `BackupScope` riêng: bìa đi kèm nhóm `books` (nhóm bắt buộc). Thêm case mới vào
/// `BackupScope` sẽ ghi rawValue lạ vào `manifest.scopes` và làm bản app cũ đọc file mới bị lỗi.
public enum BackupCoverArchiver {
    public struct Report: Sendable {
        public var restoredCovers = 0
        public var skippedCovers = 0
        public var errors: [String] = []

        public init() {}
    }

    // MARK: - Xuất

    /// Chép file bìa vào staging, trả về số bìa đã gom.
    public static func stage(
        books: [BackupPayload.BookRecord],
        slugByBookId: [String: String],
        into staging: URL
    ) throws -> Int {
        var staged = 0
        for book in books where book.hasUnrecoverableCover {
            guard let slug = slugByBookId[book.bookId] else { continue }
            let coverURL = ImageCacheManager.shared.localCoverURL(for: book.bookId)
            guard FileManager.default.fileExists(atPath: coverURL.path) else { continue }
            try BackupZipArchive.stage(
                fileAt: coverURL,
                entryName: BackupPaths.cover(slug: slug),
                in: staging
            )
            staged += 1
        }
        return staged
    }

    // MARK: - Khôi phục

    /// Ghi bìa từ archive về `covers/`. Đúng luật gộp của phân hệ backup: máy đang có bìa thì
    /// giữ bìa của máy, chỉ điền chỗ còn thiếu. Chép nguyên byte JPEG, không giải mã lại qua
    /// UIKit để bìa không bị nén thêm một lần nữa.
    public static func restore(
        books: [BackupPayload.BookRecord],
        bookIdBySlug: [String: String],
        from directory: URL
    ) -> Report {
        var report = Report()
        var slugByBookId: [String: String] = [:]
        for (slug, bookId) in bookIdBySlug { slugByBookId[bookId] = slug }

        for book in books {
            guard let slug = slugByBookId[book.bookId],
                  let source = BackupZipArchive.stagedURL(
                      entryName: BackupPaths.cover(slug: slug),
                      in: directory
                  )
            else { continue }

            let destination = ImageCacheManager.shared.localCoverURL(for: book.bookId)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                report.skippedCovers += 1
                continue
            }
            do {
                try Data(contentsOf: source).write(to: destination, options: .atomic)
                report.restoredCovers += 1
            } catch {
                report.errors.append("Ảnh bìa \(book.title): \(error.localizedDescription)")
            }
        }
        return report
    }
}
