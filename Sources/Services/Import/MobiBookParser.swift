import Foundation

/// Nhánh MOBI / AZW3 / PRC: giải nén bằng `MobiArchiveReader` rồi chọn parser theo **chữ ký PalmDB**.
///
/// * `"BOOKMOBI"` (MOBI6/KF8) — thân sách là HTML ⇒ `HtmlBookParser`. MOBI6 do Calibre sinh có
///   `<mbp:pagebreak/>` mỗi chương, KF8/AZW3 là một khối HTML skeleton nên nhánh mốc trang hoặc
///   nhánh heading của HTML parser bắt được.
/// * `"TEXtREAd"` (PalmDOC, `.prc` kinh điển) — thân sách là **text thuần** ⇒ `TxtBookParser`.
///   Đây là điểm sửa của 1.3.252: trước đó mọi file PalmDB đều đi qua `HtmlBookParser`, và SwiftSoup
///   `text()` gộp mọi khoảng trắng nên toàn bộ ranh giới dòng biến mất ⇒ sách chỉ ra một chương.
///
/// Metadata EXTH (tên sách, tác giả, mô tả, bìa) thắng metadata suy từ thân sách vì nó là khai báo
/// của chính file.
enum MobiBookParser {
    static func parse(
        data: Data,
        fileName: String,
        rules: [TOCRule]? = nil,
        structure: BookImportService.StructureMode = .auto,
        encodingOverride: TextEncodingOption? = nil
    ) throws -> ParsedBook {
        let package = try MobiArchiveReader.read(data: data)
        let text = try decodedText(package: package, override: encodingOverride)

        let base: ParsedBook
        if package.isPlainText, !looksLikeHtml(text) {
            base = plainTextBook(text: text, fileName: fileName, rules: rules)
        } else {
            base = HtmlBookParser.parse(
                html: text,
                fileName: fileName,
                rules: rules,
                structure: structure
            )
        }

        return ParsedBook(
            title: package.title ?? base.title,
            chapters: base.chapters,
            author: package.author,
            desc: package.desc ?? base.desc,
            coverData: package.coverData,
            remoteCoverUrl: package.coverData == nil ? base.remoteCoverUrl : nil,
            structureNote: base.structureNote
        )
    }

    /// PalmDOC text thuần đi thẳng vào `TxtBookParser` (quy tắc TOC) — đúng một chỗ cài logic tách
    /// chương theo regex cho cả TXT, HTML và PRC.
    ///
    /// Chuẩn hoá `\r\n`, `\r` đơn và form feed thành `\n` **trước** khi tách, vì `TxtBookParser` chỉ
    /// cắt theo `\n`: file PalmDOC thời Palm OS hay dùng `\r` đơn làm kết dòng và `\u{0C}` làm mốc
    /// trang, để nguyên thì cả sách là một dòng khổng lồ và không quy tắc TOC nào khớp.
    private static func plainTextBook(
        text: String,
        fileName: String,
        rules: [TOCRule]?
    ) -> ParsedBook {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0C}", with: "\n")
        var book = TxtBookParser.parse(content: normalized, fileName: fileName, rules: rules)
        book.structureNote = "PalmDOC text thuần — quy tắc TOC (\(book.chapters.count) chương)"
        return book
    }

    /// Vài công cụ đóng gói HTML vào chữ ký `TEXtREAd`. Chỉ nhận diện khi có dấu hiệu **tường minh**
    /// ở đầu file; không suy đoán từ vài thẻ lẻ nằm giữa văn bản.
    private static func looksLikeHtml(_ text: String) -> Bool {
        let head = String(text.prefix(1024)).lowercased()
        return head.contains("<html") || head.contains("<!doctype html") || head.contains("<?xml")
    }

    /// Thứ tự bảng mã: người dùng chọn tay → `codepage` trong MOBI header → `<meta charset>` của khối
    /// HTML → auto-detect. PalmDOC không có MOBI header nên gần như luôn rơi về auto-detect.
    private static func decodedText(
        package: MobiArchiveReader.Package,
        override: TextEncodingOption?
    ) throws -> String {
        if let override {
            guard let text = TextEncodingDecoder.decode(package.textData, using: override),
                  !text.isEmpty
            else { throw BookImportService.ImportError.decodeFailed }
            return text
        }
        if let name = package.charsetName,
           let text = TextEncodingDecoder.decodeDeclared(package.textData, charsetName: name),
           !text.isEmpty {
            return text
        }
        if let declared = XhtmlTextExtractor.declaredCharsetName(in: package.textData),
           let text = TextEncodingDecoder.decodeDeclared(package.textData, charsetName: declared),
           !text.isEmpty {
            return text
        }
        let fallback = TextEncodingDecoder.decode(package.textData)
        guard !fallback.isEmpty else { throw BookImportService.ImportError.decodeFailed }
        return fallback
    }
}
