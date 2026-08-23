import Foundation

/// Nhánh PDF: **chỉ lấy lớp văn bản**, không OCR, không nhúng ảnh.
///
/// Thứ tự ưu tiên tách chương (theo roadmap Phase 3):
/// 1. **Outline** (mục lục nhúng) — đáng tin nhất, mỗi mục một chương, biên chương là biên **trang**.
/// 2. **Quy tắc TOC** trên text ghép theo thứ tự trang — đúng đường TXT, dùng khi PDF không có outline.
/// 3. **Mỗi trang một chương** — chỉ khi người dùng ép `spine`.
///
/// Sau đó `BookImportService` áp `ChapterLengthLimiter` chung cho mọi format, nên một PDF không
/// outline vẫn không bao giờ tạo ra một chương khổng lồ.
///
/// Hai giới hạn phải nói với người dùng chứ không tự xử lý:
/// * PDF scan (không có lớp văn bản) ⇒ `ImportError.noTextLayer`, app **không** OCR.
/// * PDF hỗn hợp (một phần trang là ảnh) ⇒ `warningNote` ghi rõ số trang thiếu văn bản; sheet xác nhận
///   bắt người dùng tự chấp nhận trước khi nhập phần còn lại.
enum PdfBookParser {
    /// Trang có ít hơn ngần này ký tự coi như **không có lớp văn bản** — số trang, watermark hay vài
    /// ký tự rác của bản scan vẫn cho ra text ngắn, nếu chỉ xét chuỗi rỗng thì PDF scan sẽ lọt qua.
    /// Text của các trang này **vẫn được giữ** trong nội dung: chỉ dùng ngưỡng để đếm và cảnh báo,
    /// không để loại bỏ nội dung thật (một trang bìa chương hợp lệ cũng có thể rất ngắn).
    private static let minimumCharactersPerPage = 16

    static func parse(
        fileUrl: URL,
        fileName: String,
        rules: [TOCRule]? = nil,
        structure: BookImportService.StructureMode = .auto,
        password: String? = nil
    ) throws -> ParsedBook {
        let document = try PdfDocumentReader.open(fileUrl: fileUrl, password: password)
        let pages = PdfDocumentReader.pageTexts(document)
        let textlessCount = pages.filter { $0.count < minimumCharactersPerPage }.count
        guard textlessCount < pages.count else {
            throw BookImportService.ImportError.noTextLayer
        }

        var chapters: [ParserChapter] = []
        var note = ""

        if structure == .auto || structure == .tocIndex {
            let outline = PdfDocumentReader.outlineEntries(document)
            let fromOutline = outlineChapters(outline, pages: pages)
            if fromOutline.count >= 2 || (structure == .tocIndex && !fromOutline.isEmpty) {
                chapters = fromOutline
                note = "Outline PDF — \(fromOutline.count) chương"
            }
        }

        if chapters.isEmpty && structure == .spine {
            chapters = pageChapters(pages)
            note = "Mỗi trang một chương — \(chapters.count) chương"
        }

        if chapters.isEmpty {
            let joined = pages.filter { !$0.isEmpty }.joined(separator: "\n")
            let byRules = TxtBookParser.parse(content: joined, fileName: fileName, rules: rules)
            chapters = byRules.chapters
            note = structure == .tocIndex
                ? "PDF không có outline dùng được — quy tắc TOC, \(chapters.count) chương"
                : "Quy tắc TOC — \(chapters.count) chương"
        }

        guard !chapters.isEmpty else { throw BookImportService.ImportError.emptyContent }

        let metadata = PdfDocumentReader.metadata(document)
        return ParsedBook(
            title: metadata.title ?? TxtBookParser.bookTitle(fromFileName: fileName),
            chapters: chapters,
            author: metadata.author,
            desc: metadata.desc,
            structureNote: note,
            warningNote: textlessCount > 0
                ? "\(textlessCount)/\(pages.count) trang không có lớp văn bản (ảnh scan) nên phần đó"
                    + " không được nhập. App không hỗ trợ OCR."
                : nil
        )
    }

    // MARK: - Outline

    /// Mỗi mục outline một chương, nội dung là các trang từ mục này tới trước mục kế tiếp.
    ///
    /// Biên chương chỉ tới được mức **trang**: nhiều mục trỏ cùng một trang thì gộp về mục đầu (giữ
    /// tiêu đề của nó) — cắt trong lòng trang cần toạ độ đích, không đáng đổi lấy rủi ro sai thứ tự.
    /// Mục trỏ lùi lại trang trước cũng bị bỏ để dãy trang luôn tăng.
    private static func outlineChapters(
        _ entries: [PdfDocumentReader.OutlineEntry],
        pages: [String]
    ) -> [ParserChapter] {
        var starts: [(title: String, page: Int)] = []
        for entry in entries {
            guard entry.pageIndex >= 0, entry.pageIndex < pages.count else { continue }
            if let last = starts.last, entry.pageIndex <= last.page { continue }
            starts.append((title: entry.title, page: entry.pageIndex))
        }
        guard !starts.isEmpty else { return [] }

        var chapters: [ParserChapter] = []

        // Phần nằm trước mục outline đầu tiên (bìa, lời tựa) không thuộc chương nào — giữ như TXT.
        if starts[0].page > 0 {
            let intro = joined(pages, from: 0, to: starts[0].page)
            if !intro.isEmpty {
                chapters.append(ParserChapter(title: "Mở đầu", content: intro))
            }
        }

        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1].page : pages.count
            let title = start.title.isEmpty ? "Trang \(start.page + 1)" : start.title
            let body = joined(pages, from: start.page, to: end)
            let content = XhtmlTextExtractor.dropLeadingTitle(body, title: title)
            guard !content.isEmpty else { continue }
            chapters.append(ParserChapter(title: title, content: content))
        }
        return chapters
    }

    // MARK: - Helpers

    private static func pageChapters(_ pages: [String]) -> [ParserChapter] {
        var chapters: [ParserChapter] = []
        for (index, text) in pages.enumerated() where !text.isEmpty {
            chapters.append(ParserChapter(title: "Trang \(index + 1)", content: text))
        }
        return chapters
    }

    private static func joined(_ pages: [String], from start: Int, to end: Int) -> String {
        let slice = pages[max(0, start)..<min(pages.count, max(start, end))]
        return slice.filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
