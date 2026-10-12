import Foundation

/// Các file log và việc xoay vòng chúng: `app_logs.txt` là file đang ghi, các file cũ là `app_logs.1.txt`
/// (mới nhất) … `app_logs.<archiveCount>.txt` (cũ nhất). File đang ghi vượt `maxFileBytes` thì được đẩy
/// thành `app_logs.1.txt` và bắt đầu file mới, nên tổng dung lượng log không quá
/// `(archiveCount + 1) × maxFileBytes` và mỗi file đủ nhỏ để sao chép/xuất không đơ máy.
///
/// Chỉ đổi tên và xoá file — không mở file nào, nên không tốn file descriptor.
/// Việc xoay vòng chỉ do `AppLogger` gọi trên queue ghi log của nó.
enum AppLogFiles {
    static let maxFileBytes: UInt64 = 2 * 1024 * 1024
    static let archiveCount = 4

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var currentURL: URL {
        directory.appendingPathComponent("app_logs.txt")
    }

    static func archiveURL(_ index: Int) -> URL {
        directory.appendingPathComponent("app_logs.\(index).txt")
    }

    /// Các file log đang có trên đĩa, mới nhất trước.
    static func existingURLs() -> [URL] {
        let candidates = [currentURL] + (1...archiveCount).map { archiveURL($0) }
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Bỏ file cũ nhất, lùi các file cũ một bậc rồi đổi `app_logs.txt` thành `app_logs.1.txt`.
    /// Handle đang mở trên `app_logs.txt` vẫn trỏ đúng file vừa đổi tên. Trả `true` nếu bước đổi tên
    /// `app_logs.txt` thành công (chỉ khi đó mới có file mới để mở).
    @discardableResult
    static func shiftForRotation() -> Bool {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: archiveURL(archiveCount))
        for index in stride(from: archiveCount - 1, through: 1, by: -1) {
            try? fileManager.moveItem(at: archiveURL(index), to: archiveURL(index + 1))
        }
        return (try? fileManager.moveItem(at: currentURL, to: archiveURL(1))) != nil
    }

    /// Xoá mọi file log cũ (không đụng file đang ghi).
    static func removeArchives() {
        for index in 1...archiveCount {
            try? FileManager.default.removeItem(at: archiveURL(index))
        }
    }
}
