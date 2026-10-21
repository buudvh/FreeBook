import Foundation

/// Thông tin sách (spec §5.3).
extension LegadoSourceRuntime {
    /// Thông tin sách → `NovelDetailResult`. `link` = **đúng** `bookUrl` truyền vào (khoá nhận diện sách trên kệ).
    /// Trường rỗng của `ruleBookInfo` giữ giá trị đã biết (ngữ cảnh/trạng thái) để trang chi tiết không bị xoá trắng.
    static func detail(_ target: Target, bookUrl: String, context: SourceRuntimeContext?, log: LegadoRunLog? = nil) async throws -> NovelDetailResult {
        let info = try await resolveBookInfo(target, bookUrl: bookUrl, context: context, log: log).info
        LegadoCoverDecoder.shared.register(rawCoverURLs: [info.coverUrl], target: target)
        return NovelDetailResult(
            name: info.name,
            author: info.author,
            cover: displayCoverURL(info.coverUrl),
            description: info.intro,
            detail: detailText(info),
            host: "",
            link: bookUrl,
            genres: genres(fromKind: info.kind),
            suggests: [],
            comments: []
        )
    }

    /// Chạy thông tin sách, **gộp** với lượt đang chạy cho cùng sách (trang chi tiết tải thông tin và mục lục song song),
    /// rồi áp `tocUrl` + biến vào kho trạng thái.
    static func resolveBookInfo(_ target: Target, bookUrl: String, context: SourceRuntimeContext?, log: LegadoRunLog?) async throws -> BookInfoResult {
        let key = LegadoBookStateStore.memoryKey(packageId: target.packageId, bookUrl: bookUrl)
        return try await LegadoBookInfoCoalescer.shared.run(key: key) {
            try await Self.runBookInfo(target, bookUrl: bookUrl, context: context, log: log)
        }
    }

    private static func runBookInfo(_ target: Target, bookUrl: String, context: SourceRuntimeContext?, log: LegadoRunLog?) async throws -> BookInfoResult {
        let bookId = context?.bookId
        let persist = await shouldPersist(bookId: bookId)
        let store = LegadoBookStateStore.shared
        let initial = store.state(packageId: target.packageId, bookUrl: bookUrl, bookId: bookId)
        let book = makeBookContext(target, bookUrl: bookUrl, state: initial, context: context)
        let rule = target.source.ruleBookInfo
        let raw: BookInfo = try await runSession(target, book: book, log: log) { session in
            let response = try session.fetch(bookUrl)
            let info = try Self.evaluateBookInfo(session: session, response: response, rule: rule, book: book)
            if info.name.isEmpty, book.name.isEmpty, Self.hasHardFailure(session) {
                throw Self.emptyResultError(session, "ruleBookInfo.name")
            }
            return info
        }
        let merged = mergedInfo(book, tocUrl: raw.tocUrl)
        var delta = LegadoBookStateDelta(tocUrl: raw.tocUrl, info: stateInfo(merged))
        // `book.setReverseToc` hay gặp ở `ruleBookInfo.name` (spec §13.5) — lưu cờ để lượt mục lục áp.
        delta.recordOverrides(book)
        delta.recordBook(book, initial: initial)
        store.commit(delta, packageId: target.packageId, bookUrl: bookUrl, bookId: bookId, persist: persist)
        let state = store.state(packageId: target.packageId, bookUrl: bookUrl, bookId: bookId)
        return BookInfoResult(info: merged, state: state)
    }

    /// Đánh giá `ruleBookInfo` trên một trang sách (spec §5.3.1): `init` (phần tử đầu thành nội dung hiện hành; rỗng ⇒
    /// giữ cả trang), rồi `name, author, kind, coverUrl, intro, lastChapter, wordCount, tocUrl`. Giá trị không rỗng ghi
    /// đè lên `book` ngay để rule sau đọc được `{{book.name}}`. Trả giá trị **thô** của trang (rỗng nếu rule ra rỗng).
    static func evaluateBookInfo(
        session: LegadoEngineSession,
        response: LegadoHTTPResponse,
        rule: LegadoBookInfoRule,
        book: LegadoBookContext
    ) throws -> BookInfo {
        let analyzer = session.analyzer(response: response)
        let scope: LegadoContentNode?
        if nonEmpty(rule.initRule) != nil {
            scope = try analyzer.elements(rule.initRule).first
        } else {
            scope = nil
        }
        let name = try LegadoRuleValue.collapseWhitespace(analyzer.string(rule.name, in: scope))
        if !name.isEmpty { book.name = name }
        let author = try LegadoRuleValue.collapseWhitespace(analyzer.string(rule.author, in: scope))
        if !author.isEmpty { book.author = author }
        let kind = try LegadoRuleValue.splitKinds(analyzer.string(rule.kind, in: scope)).joined(separator: ",")
        if !kind.isEmpty { book.kind = kind }
        let coverUrl = try analyzer.url(rule.coverUrl, in: scope)
        if !coverUrl.isEmpty { book.coverUrl = coverUrl }
        let intro = try LegadoHTMLText.plainText(fromHTML: analyzer.string(rule.intro, in: scope))
        if !intro.isEmpty { book.intro = intro }
        let lastChapter = try trimmed(analyzer.string(rule.lastChapter, in: scope))
        if !lastChapter.isEmpty { book.latestChapterTitle = lastChapter }
        let wordCount = try trimmed(analyzer.string(rule.wordCount, in: scope))
        if !wordCount.isEmpty { book.wordCount = wordCount }
        let tocUrl = try analyzer.url(rule.tocUrl, in: scope)
        // `tocUrl` rỗng = mục lục nằm trên chính trang sách (§5.3.1 bước 5): JS của mục lục thấy URL cuối của trang.
        book.tocUrl = tocUrl.isEmpty ? response.finalURL : tocUrl
        return BookInfo(name: name, author: author, kind: kind, wordCount: wordCount, lastChapter: lastChapter,
                        intro: intro, coverUrl: coverUrl, tocUrl: tocUrl)
    }

    /// `evaluateBookInfo` chỉ ghi đè trường không rỗng lên `book` (§5.3.1 bước 4) ⇒ đọc lại `book` là được giá trị đã
    /// ghép (trang mới → trạng thái cũ → ngữ cảnh). Gọi **sau** khi phiên kết thúc.
    static func mergedInfo(_ book: LegadoBookContext, tocUrl: String) -> BookInfo {
        BookInfo(name: book.name, author: book.author, kind: book.kind, wordCount: book.wordCount,
                 lastChapter: book.latestChapterTitle, intro: book.intro, coverUrl: book.coverUrl, tocUrl: tocUrl)
    }

    static func stateInfo(_ info: BookInfo) -> LegadoBookState.Info {
        LegadoBookState.Info(name: info.name, author: info.author, kind: info.kind, coverUrl: info.coverUrl,
                             intro: info.intro, latestChapterTitle: info.lastChapter, wordCount: info.wordCount)
    }

    /// Dòng phụ của trang chi tiết: chương mới nhất, số chữ.
    static func detailText(_ info: BookInfo) -> String {
        var lines: [String] = []
        if !info.lastChapter.isEmpty { lines.append("Chương mới nhất: \(info.lastChapter)") }
        if !info.wordCount.isEmpty { lines.append("Số chữ: \(info.wordCount)") }
        return lines.joined(separator: "\n")
    }

    /// `kind` → thẻ thể loại của trang chi tiết. Nguồn Legado không có danh sách theo thẻ: `script` để **rỗng** —
    /// `SourceRuntime.executeCustomScript` với tên rỗng ném lỗi rõ ràng, không bao giờ chạy script JS lạ.
    static func genres(fromKind kind: String) -> [CategoryResult] {
        LegadoRuleValue.splitKinds(kind).map { CategoryResult(title: $0, input: $0, script: "") }
    }
}
