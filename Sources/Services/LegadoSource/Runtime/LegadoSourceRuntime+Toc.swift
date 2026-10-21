import Foundation

/// Mục lục (spec §5.4) với phân trang `nextTocUrl` (§5.6).
extension LegadoSourceRuntime {
    /// Một chương của mục lục (spec §5.11). Mục tên tập (`isVolume`) đã bị loại.
    struct TocEntry: Sendable {
        var name: String
        var url: String
        var isVip: Bool
        var isPay: Bool
        var updateTime: String
    }

    struct TocOutcome: Sendable {
        var entries: [TocEntry]
        /// Biến `chapter.putVariable` đặt trong lúc dựng mục lục, theo URL chương.
        var chapterVariables: [String: [String: String]]
        /// Thông tin sách nếu phiên phải chạy lại thông tin sách (`tocUrl` cũ hỏng).
        var refreshedInfo: BookInfo?
    }

    /// Mục lục của sách ở `bookUrl` (URL **trang chi tiết**, như tiện ích JS). `tocUrl` lấy từ kho trạng thái; chưa có
    /// thì chạy thông tin sách trước (gộp với lượt `detail` đang chạy). Mục tên tập bị loại, chương còn lại đánh số
    /// liên tục. `ChapterResult.url` giữ nguyên khối option `,{…}` (khoá nhận diện chương + cần để tải nội dung).
    static func toc(_ target: Target, bookUrl: String, context: SourceRuntimeContext?, log: LegadoRunLog? = nil) async throws -> [ChapterResult] {
        let bookId = context?.bookId
        let store = LegadoBookStateStore.shared
        var initial = store.state(packageId: target.packageId, bookUrl: bookUrl, bookId: bookId)
        // `tocUrl` vừa lấy mới thì không chạy lại thông tin sách khi mục lục ra rỗng.
        let usesStoredTocUrl = initial.tocUrl != nil
        if !usesStoredTocUrl {
            initial = try await resolveBookInfo(target, bookUrl: bookUrl, context: context, log: log).state
        }
        let persist = await shouldPersist(bookId: bookId)
        let knownTocUrl = initial.tocUrl ?? ""
        let book = makeBookContext(target, bookUrl: bookUrl, state: initial, context: context)
        let outcome: TocOutcome = try await runSession(target, book: book, log: log) { session in
            try Self.runToc(session: session, target: target, book: book, bookUrl: bookUrl, knownTocUrl: knownTocUrl,
                            allowRefresh: usesStoredTocUrl)
        }

        var delta = LegadoBookStateDelta()
        if let info = outcome.refreshedInfo {
            delta.tocUrl = info.tocUrl
            delta.info = stateInfo(mergedInfo(book, tocUrl: info.tocUrl))
        }
        delta.recordBook(book, initial: initial)
        for (url, values) in outcome.chapterVariables {
            delta.recordChapter(url: url, initial: initial.chapterVariables[url] ?? [:], current: values)
        }
        store.commit(delta, packageId: target.packageId, bookUrl: bookUrl, bookId: bookId, persist: persist)

        LegadoTocURLCache.shared.store(outcome.entries.map { $0.url }, packageId: target.packageId, bookUrl: bookUrl)
        return outcome.entries.map { entry in
            ChapterResult(name: entry.name, url: entry.url, host: origin(of: entry.url))
        }
    }

    /// Thân phiên mục lục. `allowRefresh` (`tocUrl` lấy từ trạng thái đã lưu) mà ra 0 chương hoặc lỗi HTTP ⇒ chạy lại
    /// thông tin sách (trang có thể đã đổi URL mục lục) rồi thử lại một lần.
    static func runToc(
        session: LegadoEngineSession,
        target: Target,
        book: LegadoBookContext,
        bookUrl: String,
        knownTocUrl: String,
        allowRefresh: Bool
    ) throws -> TocOutcome {
        var variables: [String: [String: String]] = [:]
        do {
            let entries = try collectToc(session: session, target: target, book: book, bookUrl: bookUrl,
                                         tocUrl: knownTocUrl, firstResponse: nil, chapterVariables: &variables)
            if !entries.isEmpty {
                return TocOutcome(entries: entries, chapterVariables: variables, refreshedInfo: nil)
            }
            guard allowRefresh else { throw emptyResultError(session, "chapterList") }
        } catch let error as LegadoEngineError {
            guard allowRefresh, case .httpStatus = error else { throw error }
            session.diagnostics.record(.info, "Mục lục theo tocUrl đã lưu lỗi HTTP — chạy lại thông tin sách")
        }

        let response = try session.fetch(bookUrl)
        let info = try evaluateBookInfo(session: session, response: response, rule: target.source.ruleBookInfo, book: book)
        variables = [:]
        let entries = try collectToc(session: session, target: target, book: book, bookUrl: bookUrl, tocUrl: info.tocUrl,
                                     firstResponse: info.tocUrl.isEmpty ? response : nil, chapterVariables: &variables)
        guard !entries.isEmpty else { throw emptyResultError(session, "chapterList") }
        return TocOutcome(entries: entries, chapterVariables: variables, refreshedInfo: info)
    }

    /// Vòng phân trang mục lục (spec §5.6). `tocUrl` rỗng ⇒ mục lục nằm trên trang sách: tải lại **rule URL gốc**
    /// `bookUrl` (giữ option POST/header), hoặc dùng `firstResponse` nếu đã có.
    static func collectToc(
        session: LegadoEngineSession,
        target: Target,
        book: LegadoBookContext,
        bookUrl: String,
        tocUrl: String,
        firstResponse: LegadoHTTPResponse?,
        chapterVariables: inout [String: [String: String]]
    ) throws -> [TocEntry] {
        let rule = target.source.ruleToc
        let firstURL = tocUrl.isEmpty ? bookUrl : tocUrl
        var queue = [firstURL]
        var head = 0
        var visited: Set<String> = [LegadoURLResolver.normalizedForComparison(firstURL)]
        var seenPages: Set<String> = []
        var output: [TocEntry] = []
        var loaded = 0
        while head < queue.count, loaded < tocPageLimit {
            let pageURL = queue[head]
            head += 1
            let response: LegadoHTTPResponse
            if loaded == 0, let firstResponse {
                response = firstResponse
            } else if loaded == 0 {
                response = try session.fetch(pageURL)
            } else {
                do {
                    response = try session.fetch(pageURL)
                } catch let error as LegadoEngineError {
                    // Trang sau lỗi: giữ phần đã có (spec §5.6 "dùng phần đã có"), không bỏ cả mục lục.
                    session.diagnostics.record(.info, "Dừng phân trang mục lục: \(error.localizedDescription)")
                    break
                }
            }
            loaded += 1
            visited.insert(LegadoURLResolver.normalizedForComparison(response.finalURL))
            if loaded == 1 { book.tocUrl = response.finalURL }
            let analyzer = session.analyzer(response: response)
            let entries = try parseTocPage(session: session, analyzer: analyzer, rule: rule, book: book,
                                           startIndex: output.count, chapterVariables: &chapterVariables)
            let signature = entries.map { $0.name + "\u{1}" + $0.url }.joined(separator: "\u{2}")
            // Trang lờ tham số trả lại đúng trang trước ⇒ dừng.
            if loaded > 1, !entries.isEmpty, seenPages.contains(signature) { break }
            seenPages.insert(signature)
            output.append(contentsOf: entries)

            guard nonEmpty(rule.nextTocUrl) != nil else { continue }
            session.chapter = nil
            for next in try analyzer.urls(rule.nextTocUrl) {
                let key = LegadoURLResolver.normalizedForComparison(next)
                guard !key.isEmpty, !visited.contains(key) else { continue }
                visited.insert(key)
                queue.append(next)
            }
        }
        if head < queue.count {
            session.diagnostics.record(.info, "Mục lục vượt \(tocPageLimit) trang — dừng, dùng phần đã có")
        }
        return output
    }

    /// Các chương của một trang mục lục. Thứ tự trường: `chapterName, chapterUrl, isVolume, isVip, isPay, updateTime`
    /// (spec §5.4.1). `chapterUrl` rỗng ⇒ URL trang mục lục (truyện một trang); thiếu cả tên lẫn URL ⇒ bỏ.
    static func parseTocPage(
        session: LegadoEngineSession,
        analyzer: LegadoRuleAnalyzer,
        rule: LegadoTocRule,
        book: LegadoBookContext,
        startIndex: Int,
        chapterVariables: inout [String: [String: String]]
    ) throws -> [TocEntry] {
        let items = try analyzer.elements(rule.chapterList)
        var output: [TocEntry] = []
        defer { session.chapter = nil }
        for item in items {
            try session.checkCancellation()
            let index = startIndex + output.count
            let chapter = LegadoChapterContext(index: index, baseUrl: analyzer.baseUrl, bookUrl: book.bookUrl)
            session.chapter = chapter
            let name = try trimmed(analyzer.string(rule.chapterName, in: item))
            chapter.title = name
            var url = try analyzer.url(rule.chapterUrl, in: item)
            if url.isEmpty {
                guard !name.isEmpty else { continue }
                url = analyzer.baseUrl
            }
            chapter.url = url
            let isVolume = try LegadoRuleValue.isTruthy(analyzer.string(rule.isVolume, in: item))
            chapter.isVolume = isVolume
            let isVip = try LegadoRuleValue.isTruthy(analyzer.string(rule.isVip, in: item))
            chapter.isVip = isVip
            let isPay = try LegadoRuleValue.isTruthy(analyzer.string(rule.isPay, in: item))
            chapter.isPay = isPay
            let updateTime = try trimmed(analyzer.string(rule.updateTime, in: item))
            chapter.tag = updateTime
            if chapter.hasChanges {
                chapterVariables[url, default: [:]].merge(chapter.variables) { _, new in new }
            }
            // Tên tập là tiêu đề nhóm, không phải chương đọc được (spec §5.4.3).
            guard !isVolume else { continue }
            output.append(TocEntry(name: name.isEmpty ? "Chương \(index + 1)" : name, url: url, isVip: isVip,
                                   isPay: isPay, updateTime: updateTime))
        }
        return output
    }
}
