import Foundation
import PDFKit

/// Lớp truy cập PDFKit của đường nhập PDF: mở tài liệu, mở khoá, đọc outline, đọc text từng trang.
///
/// Tách khỏi `PdfBookParser` để chỗ tách chương không phải biết gì về PDFKit, và để **một** nơi giữ
/// các quyết định nhạy cảm:
///
/// * **Không nạp cả file vào RAM**: `PDFDocument(url:)` đọc theo trang (`page.string` chỉ dựng text
///   của trang đang hỏi), nên file vài trăm MB vẫn nhập được. Vì vậy nhánh PDF của
///   `BookImportService` truyền URL, không truyền `Data`.
/// * **Không vượt bảo vệ**: tài liệu khoá chỉ mở được bằng đúng mật khẩu người dùng nhập. PDFKit tự
///   thử mật khẩu rỗng khi khởi tạo (đúng cho file chỉ có owner password), còn lại phải `unlock`.
///   Không có đường dò/khôi phục mật khẩu nào ở đây.
/// * **Không OCR**: `page.string` rỗng nghĩa là trang không có lớp văn bản; caller báo cho người dùng
///   chứ app không tự nhận dạng ảnh.
enum PdfDocumentReader {
    /// Một mục outline (mục lục nhúng) đã làm phẳng theo thứ tự xuất hiện, kèm số trang nó trỏ tới.
    struct OutlineEntry: Sendable {
        let title: String
        let pageIndex: Int
        let depth: Int
    }

    /// Chặn outline lồng quá sâu / quá dài (file dựng máy có thể cố tình bơm phồng).
    private static let maxOutlineDepth = 8
    private static let maxOutlineEntries = 10_000

    static func open(fileUrl: URL, password: String?) throws -> PDFDocument {
        guard let document = PDFDocument(url: fileUrl) else {
            throw BookImportService.ImportError.malformed("không mở được file PDF")
        }
        if document.isLocked {
            guard let password, !password.isEmpty else {
                throw BookImportService.ImportError.passwordRequired
            }
            guard document.unlock(withPassword: password) else {
                throw BookImportService.ImportError.wrongPassword
            }
        }
        guard document.pageCount > 0 else { throw BookImportService.ImportError.emptyContent }
        return document
    }

    /// Text của từng trang theo đúng thứ tự trang; trang không có lớp văn bản trả chuỗi rỗng.
    static func pageTexts(_ document: PDFDocument) -> [String] {
        return (0..<document.pageCount).map { index in
            guard let page = document.page(at: index), let raw = page.string else { return "" }
            return normalize(raw)
        }
    }

    /// Outline đã làm phẳng. Mục không trỏ được tới trang nào bị bỏ (link ngoài, JavaScript action…).
    static func outlineEntries(_ document: PDFDocument) -> [OutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [OutlineEntry] = []
        appendChildren(of: root, depth: 0, document: document, into: &entries)
        return entries
    }

    /// Metadata chuẩn của PDF. Chuỗi rỗng/toàn khoảng trắng coi như không có.
    static func metadata(_ document: PDFDocument) -> (title: String?, author: String?, desc: String?) {
        let attributes = document.documentAttributes ?? [:]
        func value(_ key: PDFDocumentAttribute) -> String? {
            guard let text = attributes[key] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return (value(.titleAttribute), value(.authorAttribute), value(.subjectAttribute))
    }

    // MARK: - Helpers

    private static func appendChildren(
        of node: PDFOutline,
        depth: Int,
        document: PDFDocument,
        into entries: inout [OutlineEntry]
    ) {
        guard depth < maxOutlineDepth, entries.count < maxOutlineEntries else { return }
        for index in 0..<node.numberOfChildren {
            guard entries.count < maxOutlineEntries, let child = node.child(at: index) else { break }
            if let pageIndex = pageIndex(of: child, in: document) {
                let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append(OutlineEntry(
                    title: title,
                    pageIndex: pageIndex,
                    depth: depth
                ))
            }
            appendChildren(of: child, depth: depth + 1, document: document, into: &entries)
        }
    }

    /// `destination` là đường chính; outline do một số công cụ sinh chỉ có `action` kiểu GoTo.
    private static func pageIndex(of outline: PDFOutline, in document: PDFDocument) -> Int? {
        if let page = outline.destination?.page {
            return document.index(for: page)
        }
        if let action = outline.action as? PDFActionGoTo, let page = action.destination.page {
            return document.index(for: page)
        }
        return nil
    }

    /// Chuẩn hoá text một trang: bỏ `\r`, đổi form feed thành newline, đổi nbsp thành khoảng trắng,
    /// trim từng dòng và gộp nhiều dòng trống liên tiếp thành **một**. Giữ cùng dạng đầu ra với
    /// `XhtmlTextExtractor` để mọi format đổ vào `TxtBookParser` như nhau.
    private static func normalize(_ raw: String) -> String {
        let unified = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{000C}", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        var lines: [String] = []
        var blankRun = 0
        for line in unified.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blankRun += 1
                if blankRun == 1 && !lines.isEmpty { lines.append("") }
                continue
            }
            blankRun = 0
            lines.append(trimmed)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
