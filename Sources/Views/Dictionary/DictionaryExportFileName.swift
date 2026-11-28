import Foundation

/// Tên file xuất danh sách `chữ Hán=nghĩa` của một truyện: `<tiền tố>_<tên truyện>_<yyyyMMddHHmmss>.txt` — **một** chỗ
/// đặt tên cho danh sách VP / Name (`DictionaryListView`) và nút ▼ › "Xuất file" của màn duyệt name
/// (`ReaderAINameReviewSheet+Export`), để hai nơi không đặt tên lệch nhau.
enum DictionaryExportFileName {
    /// Tên truyện trong tên file xuất: **luôn** dịch như trước (tên file tiếng Việt dù tắt dịch), phồn → giản theo cấu hình
    /// của truyện (Truyện ⇒ Nguồn ⇒ Tất cả; danh sách Chung ⇒ Tất cả) — 1.3.846.
    static func nameOptions(bookId: String?, packageId: String?) -> ChineseTextPipeline.Options {
        var options: ChineseTextPipeline.Options
        if let bookId, !bookId.isEmpty {
            options = ChineseTextPipeline.options(bookId: bookId, packageId: packageId)
        } else {
            options = ChineseTextPipeline.sourceOptions(packageId: nil)
        }
        options.translates = true
        return options
    }

    /// Tên file: phần tên truyện lấy `dbTitle` (tên trong DB) ⇒ `fallbackTitle` (tên nơi gọi có sẵn) — cả hai qua
    /// `nameOptions`, dịch ra rỗng thì giữ chữ gốc — ⇒ `bookId` ⇒ "Chung"; bỏ ký tự cấm của tên file (`normalize`).
    static func make(
        prefix: String,
        dbTitle: String?,
        fallbackTitle: String,
        bookId: String?,
        packageId: String?,
        date: Date = Date()
    ) -> String {
        let namePart: String
        if let title = [dbTitle ?? "", fallbackTitle].first(where: { !$0.isEmpty }) {
            let translated = ChineseTextPipeline.meta(title, nameOptions(bookId: bookId, packageId: packageId))
            namePart = translated.isEmpty ? title : translated
        } else {
            namePart = bookId ?? "Chung"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = formatter.string(from: date)
        return "\(prefix)_\(normalize(namePart))_\(timestamp).txt"
    }

    /// Thay ký tự cấm của tên file (`/ \ : * ? " < > |`) bằng `_`, bỏ khoảng trắng hai đầu; rỗng ⇒ "Unknown".
    static func normalize(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var result = name.components(separatedBy: invalidChars).joined(separator: "_")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { result = "Unknown" }
        return result
    }

    /// Ghi `content` (UTF-8) vào thư mục tạm dưới tên `fileName` — file đưa cho bảng chia sẻ.
    static func writeTemporaryFile(_ content: String, named fileName: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
