import Foundation

/// Ghép ba mảnh EPUB (`EpubArchiveReader` → `EpubOpfParser` → `EpubNavParser`) thành `ParsedBook`.
///
/// Thứ tự rơi, dừng ở nhánh đầu tiên cho ra ≥ 2 chương:
/// 1. **mục lục thật** (`toc.ncx` của EPUB2 hoặc tài liệu `nav` của EPUB3) — đáng tin nhất;
/// 2. **thứ tự spine** — mỗi document một chương;
/// 3. **quy tắc TOC** trên text của toàn bộ spine (đúng đường TXT đang chạy).
///
/// Toàn bộ nội dung được đọc vào RAM **trước** khi `defer` xoá thư mục giải nén, nên caller không
/// phải dọn gì thêm.
enum EpubBookParser {
    static func parse(
        fileUrl: URL,
        fileName: String,
        rules: [TOCRule]? = nil,
        structure: BookImportService.StructureMode = .auto
    ) throws -> ParsedBook {
        let package = try EpubArchiveReader.read(fileUrl: fileUrl)
        defer { try? FileManager.default.removeItem(at: package.rootDirectory) }

        let manifest = try EpubOpfParser.parse(opfURL: package.opfURL)
        let documents = spineDocuments(package: package, manifest: manifest)

        var chapters: [ParserChapter] = []
        var note: String?

        if structure == .auto || structure == .tocIndex,
           let toc = tocEntries(package: package, manifest: manifest) {
            let built = chaptersFromToc(entries: toc.entries, base: toc.base, package: package)
            if built.count >= 2 || (structure == .tocIndex && !built.isEmpty) {
                chapters = built
                note = "\(toc.sourceName) — \(built.count) chương"
            }
        }

        if chapters.isEmpty, structure == .auto || structure == .spine {
            let built = chaptersFromSpine(documents)
            if built.count >= 2 || (structure == .spine && !built.isEmpty) {
                chapters = built
                note = "Thứ tự file trong EPUB — \(built.count) chương"
            }
        }

        if chapters.isEmpty {
            let text = documents.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
            let byRules = TxtBookParser.parse(content: text, fileName: fileName, rules: rules).chapters
            if byRules.count >= 2 {
                chapters = byRules
                note = "Quy tắc TOC — \(byRules.count) chương"
            } else if !text.isEmpty {
                let title = manifest.title ?? TxtBookParser.bookTitle(fromFileName: fileName)
                chapters = [ParserChapter(title: title, content: text)]
                note = "Không tìm thấy ranh giới chương — giữ 1 chương"
            }
        }

        return ParsedBook(
            title: manifest.title ?? TxtBookParser.bookTitle(fromFileName: fileName),
            chapters: chapters,
            author: manifest.author,
            desc: manifest.desc,
            coverData: coverData(package: package, manifest: manifest, documents: documents),
            structureNote: note
        )
    }

    // MARK: - Spine

    /// Một document trong spine đã đọc sẵn cả HTML lẫn text (dùng lại cho mọi nhánh, khỏi đọc đĩa 2 lần).
    private struct Document {
        let itemId: String
        let path: String
        let html: String
        let text: String
    }

    private static func spineDocuments(
        package: EpubArchiveReader.Package,
        manifest: EpubOpfParser.Manifest
    ) -> [Document] {
        var documents: [Document] = []
        for idref in manifest.spine {
            guard let item = manifest.items[idref] else { continue }
            // Bỏ ảnh/CSS lỡ nằm trong spine, và bỏ chính tài liệu nav (nó là mục lục, không phải chương).
            guard item.mediaType.isEmpty || item.mediaType.contains("html") else { continue }
            guard idref != manifest.navId else { continue }
            guard let url = package.resolve(href: item.href),
                  let html = readText(at: url)
            else { continue }
            documents.append(Document(
                itemId: idref,
                path: item.href,
                html: html,
                text: XhtmlTextExtractor.plainText(html: html)
            ))
        }
        return documents
    }

    private static func chaptersFromSpine(_ documents: [Document]) -> [ParserChapter] {
        var chapters: [ParserChapter] = []
        for document in documents {
            guard !document.text.isEmpty else { continue }
            let title = XhtmlTextExtractor.firstHeading(html: document.html)
                ?? "Chương \(chapters.count + 1)"
            chapters.append(ParserChapter(
                title: title,
                content: XhtmlTextExtractor.dropLeadingTitle(document.text, title: title)
            ))
        }
        return chapters
    }

    // MARK: - Mục lục thật

    /// Mục lục đọc được cùng thư mục gốc để giải href (href trong NCX/nav là tương đối với **file
    /// mục lục**, không phải với OPF) và tên nhánh để hiện trên sheet.
    private struct Toc {
        let entries: [EpubNavParser.Entry]
        let base: URL
        let sourceName: String
    }

    private static func tocEntries(
        package: EpubArchiveReader.Package,
        manifest: EpubOpfParser.Manifest
    ) -> Toc? {
        var candidates: [Toc] = []

        if let url = tocFileURL(package: package, manifest: manifest, isNcx: true),
           let data = try? Data(contentsOf: url) {
            let entries = EpubNavParser.parseNcx(data: data)
            if !entries.isEmpty {
                candidates.append(Toc(
                    entries: entries,
                    base: url.deletingLastPathComponent(),
                    sourceName: "Mục lục NCX"
                ))
            }
        }

        if let url = tocFileURL(package: package, manifest: manifest, isNcx: false),
           let html = readText(at: url) {
            let entries = EpubNavParser.parseNav(html: html)
            if !entries.isEmpty {
                candidates.append(Toc(
                    entries: entries,
                    base: url.deletingLastPathComponent(),
                    sourceName: "Mục lục EPUB3"
                ))
            }
        }

        // Mục lục nào liệt kê nhiều mục hơn thì sát chương hơn: NCX của EPUB3 lai thường bị rút gọn.
        return candidates.max { $0.entries.count < $1.entries.count }
    }

    private static func tocFileURL(
        package: EpubArchiveReader.Package,
        manifest: EpubOpfParser.Manifest,
        isNcx: Bool
    ) -> URL? {
        let declaredId = isNcx ? manifest.ncxId : manifest.navId
        if let declaredId, let item = manifest.items[declaredId],
           let url = package.resolve(href: item.href) {
            return url
        }
        // OPF thiếu khai báo: tìm theo media type, rồi tới tên file quen thuộc.
        let mediaType = isNcx ? "dtbncx" : "html"
        let fallback = manifest.items.values.first { item in
            if isNcx {
                return item.mediaType.contains(mediaType)
                    || item.href.lowercased().hasSuffix(".ncx")
            }
            return item.mediaType.contains(mediaType)
                && item.href.lowercased().contains("nav")
        }
        guard let fallback else { return nil }
        return package.resolve(href: fallback.href)
    }

    /// Mỗi `Entry` một chương. Nhiều `Entry` trỏ cùng một file:
    /// * có `#fragment` ⇒ cắt theo id neo (`XhtmlTextExtractor.anchorSegments`);
    /// * không có fragment ⇒ chỉ lấy một lần (khử trùng), tránh nhân bản cả file.
    private static func chaptersFromToc(
        entries: [EpubNavParser.Entry],
        base: URL,
        package: EpubArchiveReader.Package
    ) -> [ParserChapter] {
        var fragmentsByPath: [String: [String]] = [:]
        for entry in entries {
            guard let fragment = entry.fragment else { continue }
            fragmentsByPath[entry.path, default: []].append(fragment)
        }

        var htmlCache: [String: String] = [:]
        var segmentCache: [String: [String: String]] = [:]
        var wholeFileTaken: Set<String> = []
        var chapters: [ParserChapter] = []

        for entry in entries {
            let path = entry.path
            let html: String
            if let cached = htmlCache[path] {
                html = cached
            } else {
                guard let url = package.resolve(href: path, base: base),
                      let loaded = readText(at: url)
                else { continue }
                html = loaded
                htmlCache[path] = loaded
            }

            let fragments = fragmentsByPath[path] ?? []
            var text = ""
            if let fragment = entry.fragment, fragments.count >= 2 {
                let segments: [String: String]
                if let cached = segmentCache[path] {
                    segments = cached
                } else {
                    segments = XhtmlTextExtractor.anchorSegments(html: html, anchorIds: fragments)
                    segmentCache[path] = segments
                }
                text = segments[fragment] ?? ""
            }
            if text.isEmpty {
                // Không có fragment, hoặc id neo không tồn tại trong file ⇒ dùng cả file, một lần.
                guard !wholeFileTaken.contains(path) else { continue }
                wholeFileTaken.insert(path)
                text = XhtmlTextExtractor.plainText(html: html)
            }
            guard !text.isEmpty else { continue }

            let title = entry.title.isEmpty
                ? (XhtmlTextExtractor.firstHeading(html: html) ?? "Chương \(chapters.count + 1)")
                : entry.title
            chapters.append(ParserChapter(
                title: title,
                content: XhtmlTextExtractor.dropLeadingTitle(text, title: title)
            ))
        }
        return chapters
    }

    // MARK: - Ảnh bìa

    /// Thứ tự thử: item bìa khai trong OPF (ảnh trực tiếp, hoặc trang bìa XHTML → `<img>` trong đó),
    /// rồi `<img>` đầu tiên của document spine đầu.
    private static func coverData(
        package: EpubArchiveReader.Package,
        manifest: EpubOpfParser.Manifest,
        documents: [Document]
    ) -> Data? {
        if let coverId = manifest.coverId, let item = manifest.items[coverId] {
            if item.mediaType.contains("image") || !isMarkup(item) {
                if let url = package.resolve(href: item.href),
                   let data = try? Data(contentsOf: url), !data.isEmpty {
                    return data
                }
            } else if let url = package.resolve(href: item.href),
                      let html = readText(at: url) {
                if let data = imageData(from: html, base: url.deletingLastPathComponent(), package: package) {
                    return data
                }
            }
        }
        guard let first = documents.first,
              let url = package.resolve(href: first.path)
        else { return nil }
        return imageData(from: first.html, base: url.deletingLastPathComponent(), package: package)
    }

    private static func isMarkup(_ item: EpubOpfParser.Item) -> Bool {
        return item.mediaType.contains("html") || item.href.lowercased().hasSuffix("html")
    }

    private static func imageData(
        from html: String,
        base: URL,
        package: EpubArchiveReader.Package
    ) -> Data? {
        guard let src = XhtmlTextExtractor.firstImageSrc(html: html),
              !src.lowercased().hasPrefix("http"),
              !src.lowercased().hasPrefix("data:"),
              let url = package.resolve(href: src, base: base),
              let data = try? Data(contentsOf: url), !data.isEmpty
        else { return nil }
        return data
    }

    // MARK: - Đọc file

    /// XHTML trong EPUB theo chuẩn là UTF-8; file cũ đôi khi khai `<?xml encoding="…"?>` khác.
    private static func readText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let declared = XhtmlTextExtractor.declaredCharsetName(in: data),
           let text = TextEncodingDecoder.decodeDeclared(data, charsetName: declared),
           !text.isEmpty {
            return text
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty { return text }
        let fallback = TextEncodingDecoder.decode(data)
        return fallback.isEmpty ? nil : fallback
    }
}
