import Foundation

/// Tìm kiếm (spec §5.1) và phần bóc danh sách sách dùng chung với Khám phá (§5.2.4).
extension LegadoSourceRuntime {
    /// Một trang kết quả tìm `query`. 0 kết quả mà chẩn đoán sạch ⇒ `[]` (giống tiện ích JS); 0 kết quả kèm lỗi JS /
    /// hàm chưa hỗ trợ ⇒ ném để bộ nghiệm thu phân loại.
    static func search(_ target: Target, query: String, page: Int, log: LegadoRunLog? = nil) async throws -> [ExtensionItemResult] {
        let searchUrl = target.source.searchUrl
        guard nonEmpty(searchUrl) != nil else { throw LegadoRuntimeError.missingRule("searchUrl") }
        let key = trimmed(query)
        let pageNumber = max(1, page)
        // `searchUrl` không có chỗ cắm số trang thì trang 2+ chỉ là trang 1 lặp lại (spec §5.1.1 bước 5).
        if pageNumber > 1, !hasPagePlaceholder(searchUrl) { return [] }
        let books: [FoundBook] = try await runSession(target, log: log) { session in
            session.key = key
            session.page = pageNumber
            let response = try session.fetch(searchUrl, key: key, page: pageNumber)
            let analyzer = session.analyzer(response: response)
            let extracted = try Self.extractBooksCounting(session: session, analyzer: analyzer, rule: target.source.ruleSearch)
            var found = extracted.books
            if found.isEmpty, let direct = try Self.directBookPage(session: session, target: target, response: response) {
                found = [direct]
            }
            if found.isEmpty {
                // Đầu dò bộ chọn (chỉ khi lượt chạy có log): bằng chứng "nguồn lỗi thời" hay "nghi do app".
                LegadoSelectorProbe.record(in: session, field: "bookList", rule: target.source.ruleSearch.bookList,
                                           response: response, matchedElements: extracted.matched)
            }
            if found.isEmpty, Self.hasHardFailure(session) {
                throw Self.emptyResultError(session, "bookList")
            }
            return found
        }
        stashFoundBooks(books, target: target)
        LegadoCoverDecoder.shared.register(rawCoverURLs: books.map { $0.coverUrl }, target: target)
        return books.map { itemResult($0) }
    }

    /// Bóc các mục của rule danh sách (`bookList` + trường) trên một trang. Đánh giá trường theo thứ tự cố định
    /// `name, author, kind, wordCount, lastChapter, intro, coverUrl, bookUrl` (spec §6.2) và gán dần vào `book` của mục
    /// để rule sau đọc được `{{book.name}}`. Bỏ mục thiếu `name` hoặc `bookUrl` (§5.1.1 bước 4).
    static func extractBooks(session: LegadoEngineSession, analyzer: LegadoRuleAnalyzer, rule: LegadoSearchRule) throws -> [FoundBook] {
        try extractBooksCounting(session: session, analyzer: analyzer, rule: rule).books
    }

    /// Như `extractBooks`, trả thêm số phần tử `bookList` khớp **trước** khi lọc mục thiếu tên/link (đầu dò bộ chọn).
    static func extractBooksCounting(
        session: LegadoEngineSession,
        analyzer: LegadoRuleAnalyzer,
        rule: LegadoSearchRule
    ) throws -> (books: [FoundBook], matched: Int) {
        let items = try analyzer.elements(rule.bookList)
        var output: [FoundBook] = []
        let savedBook = session.book
        defer { session.book = savedBook }
        for item in items {
            try session.checkCancellation()
            let book = LegadoBookContext(origin: session.source.key, originName: session.source.name, type: session.source.type)
            session.book = book
            let name = try LegadoRuleValue.collapseWhitespace(analyzer.string(rule.name, in: item))
            book.name = name
            let author = try LegadoRuleValue.collapseWhitespace(analyzer.string(rule.author, in: item))
            book.author = author
            let kind = try LegadoRuleValue.splitKinds(analyzer.string(rule.kind, in: item)).joined(separator: ",")
            book.kind = kind
            let wordCount = try trimmed(analyzer.string(rule.wordCount, in: item))
            book.wordCount = wordCount
            let lastChapter = try trimmed(analyzer.string(rule.lastChapter, in: item))
            book.latestChapterTitle = lastChapter
            let intro = try LegadoHTMLText.plainText(fromHTML: analyzer.string(rule.intro, in: item))
            book.intro = intro
            let coverUrl = try analyzer.url(rule.coverUrl, in: item)
            book.coverUrl = coverUrl
            let bookUrl = try analyzer.url(rule.bookUrl, in: item)
            book.bookUrl = bookUrl
            guard !name.isEmpty, !bookUrl.isEmpty else { continue }
            output.append(FoundBook(
                name: name, author: author, kind: kind, wordCount: wordCount, lastChapter: lastChapter, intro: intro,
                coverUrl: coverUrl, bookUrl: bookUrl, variables: book.variables, ruleVariables: book.ruleVariables,
                tocUrl: nil
            ))
        }
        return (output, items.count)
    }

    /// Trang tìm kiếm rơi thẳng vào trang sách (spec §5.1.4, khuyến nghị cho U21): `bookList` ra 0 mục **và** URL cuối
    /// của phản hồi khớp **toàn chuỗi** `bookUrlPattern` ⇒ chạy thông tin sách lên chính trang đó, ra đúng một mục.
    /// Khớp một phần thì không tính (pattern rác kiểu `https://www.x.com` khớp cả trang tìm kiếm).
    static func directBookPage(session: LegadoEngineSession, target: Target, response: LegadoHTTPResponse) throws -> FoundBook? {
        guard let pattern = nonEmpty(target.source.bookUrlPattern),
              let regex = LegadoRegexCache.shared.regex(pattern) else { return nil }
        let finalURL = response.finalURL
        let range = NSRange(finalURL.startIndex..., in: finalURL)
        guard let match = regex.firstMatch(in: finalURL, options: [.anchored], range: range),
              match.range.location == 0, match.range.length == range.length else { return nil }
        let book = LegadoBookContext(bookUrl: finalURL, origin: session.source.key, originName: session.source.name,
                                     type: session.source.type)
        let savedBook = session.book
        session.book = book
        defer { session.book = savedBook }
        let info = try evaluateBookInfo(session: session, response: response, rule: target.source.ruleBookInfo, book: book)
        guard !info.name.isEmpty else { return nil }
        return FoundBook(
            name: info.name, author: info.author, kind: info.kind, wordCount: info.wordCount,
            lastChapter: info.lastChapter, intro: info.intro, coverUrl: info.coverUrl, bookUrl: finalURL,
            variables: book.variables, ruleVariables: book.ruleVariables, tocUrl: info.tocUrl
        )
    }

    /// Phiên có lỗi "thật" (JS ném, hàm chưa hỗ trợ) — dùng để quyết định 0 kết quả là lỗi hay chỉ là không có gì.
    static func hasHardFailure(_ session: LegadoEngineSession) -> Bool {
        let diagnostics = session.diagnostics
        if diagnostics.unsupportedFeatures.contains(where: { !$0.contains("bỏ qua") }) { return true }
        return diagnostics.count(of: .javaScript) > 0
    }
}
