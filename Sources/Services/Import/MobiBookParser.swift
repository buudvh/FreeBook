import Foundation

/// Nhánh MOBI/AZW3: giải nén bằng `MobiArchiveReader` rồi đưa **thẳng** khối HTML thu được vào
/// `HtmlBookParser` — MOBI6 do Calibre sinh có `<mbp:pagebreak/>` mỗi chương, KF8/AZW3 là một khối
/// HTML skeleton nên nhánh mốc trang hoặc nhánh heading của HTML parser bắt được.
///
/// Metadata EXTH (tên sách, tác giả, mô tả, bìa) thắng metadata suy từ HTML vì nó là khai báo của
/// chính file.
enum MobiBookParser {
    static func parse(
        data: Data,
        fileName: String,
        rules: [TOCRule]? = nil,
        structure: BookImportService.StructureMode = .auto,
        encodingOverride: TextEncodingOption? = nil
    ) throws -> ParsedBook {
        let package = try MobiArchiveReader.read(data: data)
        let html = try decodedHtml(package: package, override: encodingOverride)

        let base = HtmlBookParser.parse(
            html: html,
            fileName: fileName,
            rules: rules,
            structure: structure
        )
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

    /// Thứ tự bảng mã: người dùng chọn tay → `codepage` trong MOBI header → `<meta charset>` của khối
    /// HTML → auto-detect.
    private static func decodedHtml(
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
