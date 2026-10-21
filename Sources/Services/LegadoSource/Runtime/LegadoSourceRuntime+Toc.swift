import Foundation

/// Mục lục (spec §5.4) với phân trang `nextTocUrl` (§5.6).
extension LegadoSourceRuntime {
    /// Một chương của mục lục (spec §5.11). Truyện chữ: mục tên tập (`isVolume`) bị loại. Tranh/video: mục tên tập giữ
    /// thành dòng tiêu đề nhóm (`isVolume == true` ⇒ `ChapterResult.isSection`, spec §9.2).
    struct TocEntry: Sendable {
        var name: String
        var url: String
        var isVip: Bool
        var isPay: Bool
        var updateTime: String
        var isVolume: Bool = false
    }

    struct TocOutcome: Sendable {
        var entries: [TocEntry]
        /// Biến `chapter.putVariable` đặt trong lúc dựng mục lục, theo URL chương.
        var chapterVariables: [String: [String: String]]
        /// Thông tin sách nếu phiên phải chạy lại thông tin sách (`tocUrl` cũ hỏng, hoặc `java.refreshTocUrl()`).
        var refreshedInfo: BookInfo?
        /// `tocUrl` do `preUpdateJs` ghi (không qua `refreshTocUrl`) — lưu bền (spec §13.5).
        var tocUrlOverride: String? = nil
    }

    /// Mục lục của sách ở `bookUrl` (URL **trang chi tiết**, như tiện ích JS). `tocUrl` lấy từ kho trạng thái; chưa có
    /// thì chạy thông tin sách trước (gộp với lượt `detail` đang chạy). Truyện chữ: mục tên tập bị loại, chương còn lại
    /// đánh số liên tục; tranh/video: mục tên tập thành dòng `isSection`. Sau vòng trang: đảo theo `book.setReverseToc`,
    /// rồi `formatJs` (spec §13.4–§13.5). `ChapterResult.url` giữ nguyên khối option `,{…}` (khoá nhận diện chương + cần
    /// để tải nội dung).
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
        let storedReverse = initial.reverseToc
        let outcome: TocOutcome = try await runSession(target, book: book, log: log) { session in
            var result = try Self.runToc(session: session, target: target, book: book, bookUrl: bookUrl,
                                         knownTocUrl: knownTocUrl, allowRefresh: usesStoredTocUrl)
            // `book.setReverseToc` (spec §13.5): đảo cả danh sách sau mọi trang (sau `-` của rule), trước `formatJs`.
            // Cờ của lượt này (engine ghi lên `book`) thắng cờ đã lưu.
            if (book.reverseTocOverride ?? storedReverse) == true {
                result.entries.reverse()
            }
            result.entries = try Self.applyFormatJs(session: session, target: target, entries: result.entries)
            return result
        }

        var delta = LegadoBookStateDelta()
        if let info = outcome.refreshedInfo {
            delta.tocUrl = info.tocUrl
            delta.info = stateInfo(mergedInfo(book, tocUrl: info.tocUrl))
        } else if let tocUrl = outcome.tocUrlOverride {
            delta.tocUrl = tocUrl
        }
        delta.recordOverrides(book)
        delta.recordBook(book, initial: initial)
        for (url, values) in outcome.chapterVariables {
            delta.recordChapter(url: url, initial: initial.chapterVariables[url] ?? [:], current: values)
        }
        store.commit(delta, packageId: target.packageId, bookUrl: bookUrl, bookId: bookId, persist: persist)

        // Dòng tiêu đề nhóm giữ chỗ bằng "" để chỉ số trong bộ đệm khớp chỉ số chương của app.
        LegadoTocURLCache.shared.store(outcome.entries.map { $0.isVolume ? "" : $0.url },
                                       packageId: target.packageId, bookUrl: bookUrl)
        return outcome.entries.map { entry in
            ChapterResult(name: entry.name, url: entry.url, host: origin(of: entry.url), isSection: entry.isVolume)
        }
    }

    /// Thân phiên mục lục: `preUpdateJs` (spec §13.3) → vòng trang. `allowRefresh` (`tocUrl` lấy từ trạng thái đã lưu)
    /// mà ra 0 chương hoặc lỗi HTTP ⇒ chạy lại thông tin sách (trang có thể đã đổi URL mục lục) rồi thử lại một lần.
    /// Việc đảo theo `book.setReverseToc` và `formatJs` do `toc` làm sau hàm này.
    static func runToc(
        session: LegadoEngineSession,
        target: Target,
        book: LegadoBookContext,
        bookUrl: String,
        knownTocUrl: String,
        allowRefresh: Bool
    ) throws -> TocOutcome {
        try collectTocWithRefresh(session: session, target: target, book: book, bookUrl: bookUrl,
                                  knownTocUrl: knownTocUrl, allowRefresh: allowRefresh)
    }

    private static func collectTocWithRefresh(
        session: LegadoEngineSession,
        target: Target,
        book: LegadoBookContext,
        bookUrl: String,
        knownTocUrl: String,
        allowRefresh: Bool
    ) throws -> TocOutcome {
        var effectiveBookUrl = bookUrl
        var tocUrl = knownTocUrl
        var firstResponse: LegadoHTTPResponse?
        var refreshed: BookInfo?
        var tocUrlOverride: String?
        if let pre = try runPreUpdate(session: session, target: target, book: book, bookUrl: bookUrl,
                                      knownTocUrl: knownTocUrl) {
            effectiveBookUrl = pre.bookUrl
            if let info = pre.refreshedInfo {
                refreshed = info
                tocUrl = info.tocUrl
                firstResponse = info.tocUrl.isEmpty ? pre.response : nil
            } else if let newTocUrl = pre.tocUrl {
                tocUrl = newTocUrl
                tocUrlOverride = newTocUrl
            }
        }
        let canRefresh = allowRefresh && refreshed == nil
        var variables: [String: [String: String]] = [:]
        do {
            let entries = try collectToc(session: session, target: target, book: book, bookUrl: effectiveBookUrl,
                                         tocUrl: tocUrl, firstResponse: firstResponse, chapterVariables: &variables)
            if !entries.isEmpty {
                return TocOutcome(entries: entries, chapterVariables: variables, refreshedInfo: refreshed,
                                  tocUrlOverride: tocUrlOverride)
            }
            guard canRefresh else { throw emptyResultError(session, "chapterList") }
        } catch let error as LegadoEngineError {
            guard canRefresh, case .httpStatus = error else { throw error }
            session.diagnostics.record(.info, "Mục lục theo tocUrl đã lưu lỗi HTTP — chạy lại thông tin sách")
        }

        let response = try session.fetch(effectiveBookUrl)
        let info = try evaluateBookInfo(session: session, response: response, rule: target.source.ruleBookInfo, book: book)
        variables = [:]
        let entries = try collectToc(session: session, target: target, book: book, bookUrl: effectiveBookUrl,
                                     tocUrl: info.tocUrl, firstResponse: info.tocUrl.isEmpty ? response : nil,
                                     chapterVariables: &variables)
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
        // Tranh (2) / video (4): tên tập thành dòng tiêu đề nhóm thay vì bị loại (spec §9.2).
        let keepsVolumes = session.source.type == 2 || session.source.type == 4
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
            if isVolume {
                guard keepsVolumes else { continue }
                output.append(TocEntry(name: name.isEmpty ? "Phần \(index + 1)" : name, url: url, isVip: false,
                                       isPay: false, updateTime: updateTime, isVolume: true))
                continue
            }
            output.append(TocEntry(name: name.isEmpty ? "Chương \(index + 1)" : name, url: url, isVip: isVip,
                                   isPay: isPay, updateTime: updateTime))
        }
        return output
    }
}
