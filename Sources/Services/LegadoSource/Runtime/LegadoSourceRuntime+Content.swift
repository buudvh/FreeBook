import Foundation

/// Nội dung chương (spec §5.5) với phân trang `nextContentUrl` (§5.6). Phần tải + nối trang + `replaceRegex` dùng chung
/// cho truyện chữ (rồi HTML → văn bản) và truyện tranh (rồi tách ảnh, spec §8.2) — xem `collectContent`.
extension LegadoSourceRuntime {
    /// Chuỗi HTML của một chương sau vòng trang và `replaceRegex`, **chưa** chuyển văn bản.
    struct CollectedContent {
        var html: String
        /// URL cuối của trang chương đầu — URL nền để ghép URL ảnh tương đối (spec §8.2 bước 4).
        var pageURL: String
    }

    /// Văn bản thuần của chương ở `chapterUrl` (`ChapterResult.url` nguyên văn). Mọi trang `nextContentUrl` chạy chung
    /// một phiên (một runtime JS). URL dừng = URL chương kế trong mục lục (bộ nhớ, rồi `ChapterStore`), để rule kiểu
    /// "下一章" không kéo cả truyện vào một chương. Kết quả chưa qua `ChapterTextNormalizer` — pipeline chương của app
    /// tự chuẩn hoá. Rỗng ⇒ ném (không lưu bản rỗng).
    static func content(_ target: Target, chapterUrl: String, context: SourceRuntimeContext?, log: LegadoRunLog? = nil) async throws -> String {
        try await runChapterSession(target, chapterUrl: chapterUrl, context: context, log: log) { session, nextURL in
            let text = try Self.runContent(session: session, target: target, chapterUrl: chapterUrl, stopURL: nextURL)
            guard !text.isEmpty else { throw Self.emptyResultError(session, "nội dung chương (content)") }
            return text
        }
    }

    /// Một phiên "chương" (chữ, tranh, video): nạp trạng thái truyện + ngữ cảnh `book`/`chapter`, tìm URL chương kế (URL
    /// dừng, cũng là biến JS `nextChapterUrl`), chạy `body`, rồi áp biến sách/chương đã đổi vào kho trạng thái.
    static func runChapterSession<T>(
        _ target: Target,
        chapterUrl: String,
        context: SourceRuntimeContext?,
        log: LegadoRunLog?,
        _ body: @escaping @Sendable (LegadoEngineSession, String?) throws -> T
    ) async throws -> T {
        let bookId = context?.bookId
        let store = LegadoBookStateStore.shared
        let initial = store.state(packageId: target.packageId, bookUrl: context?.bookUrl, bookId: bookId)
        let bookUrl = nonEmpty(context?.bookUrl) ?? initial.bookUrl
        let nextURL = await nextChapterURL(target, chapterUrl: chapterUrl, bookUrl: bookUrl, context: context)
        let stopKeys = await tocStopKeys(target, chapterUrl: chapterUrl, bookUrl: bookUrl, context: context)
        let persist = await shouldPersist(bookId: bookId)
        let book = makeBookContext(target, bookUrl: bookUrl, state: initial, context: context)
        let initialChapterVariables = initial.chapterVariables[chapterUrl] ?? [:]
        let chapter = LegadoChapterContext(
            title: context?.chapterTitle ?? "",
            url: chapterUrl,
            index: context?.chapterIndex ?? 0,
            baseUrl: chapterUrl,
            bookUrl: bookUrl,
            variables: initialChapterVariables
        )
        let value: T = try await runSession(target, book: book, chapter: chapter, log: log) { session in
            session.nextChapterUrl = nextURL
            session.tocStopKeys = stopKeys
            return try body(session, nextURL)
        }

        var delta = LegadoBookStateDelta()
        delta.recordOverrides(book)
        delta.recordBook(book, initial: initial)
        delta.recordChapter(url: chapterUrl, initial: initialChapterVariables, current: chapter.variables)
        store.commit(delta, packageId: target.packageId, bookUrl: nonEmpty(bookUrl), bookId: bookId, persist: persist)
        return value
    }

    /// Thân phiên nội dung chữ: `collectContent` → `LegadoHTMLText.plainText` (§5.5.2).
    static func runContent(session: LegadoEngineSession, target: Target, chapterUrl: String, stopURL: String?) throws -> String {
        let collected = try collectContent(session: session, target: target, chapterUrl: chapterUrl, stopURL: stopURL)
        return LegadoHTMLText.plainText(fromHTML: collected.html)
    }

    /// Vòng trang (spec §5.6) → nối `\n` → `replaceRegex` trên chuỗi đã nối, **trước** bước HTML → văn bản / tách ảnh
    /// (§5.5.3, khuyến nghị U17; §8.2 bước 1). `sourceRegex` (§9.4, §13.2) chuyển cho engine — chỉ có tác dụng khi
    /// request nội dung đi WebView.
    static func collectContent(session: LegadoEngineSession, target: Target, chapterUrl: String, stopURL: String?) throws -> CollectedContent {
        let rule = target.source.ruleContent
        let webJs = nonEmpty(rule.webJs)
        let sourceRegex = nonEmpty(rule.sourceRegex)
        let stopKey = stopURL.map { LegadoURLResolver.normalizedForComparison($0) }
        var queue = [chapterUrl]
        var head = 0
        var visited: Set<String> = [LegadoURLResolver.normalizedForComparison(chapterUrl)]
        var seenParts: Set<String> = []
        var parts: [String] = []
        var loaded = 0
        var firstPageURL = LegadoURLResolver.splitOption(chapterUrl).url
        while head < queue.count, loaded < contentPageLimit {
            let pageURL = queue[head]
            head += 1
            let response: LegadoHTTPResponse
            if loaded == 0 {
                response = try session.fetch(pageURL, webJs: webJs, sourceRegex: sourceRegex)
            } else {
                do {
                    response = try session.fetch(pageURL, webJs: webJs, sourceRegex: sourceRegex)
                } catch let error as LegadoEngineError {
                    session.diagnostics.record(.info, "Dừng phân trang nội dung: \(error.localizedDescription)")
                    break
                }
            }
            loaded += 1
            if loaded == 1 { firstPageURL = response.finalURL }
            visited.insert(LegadoURLResolver.normalizedForComparison(response.finalURL))
            let analyzer = session.analyzer(response: response)
            // Trường nội dung: phần tử HTML (vd danh sách `<img>` do JS trả) giữ outer HTML (spec §15.3 mục 2).
            let part = try analyzer.contentString(rule.content)
            let partKey = trimmed(part)
            // Trang lờ tham số trả lại đúng nội dung trước ⇒ dừng.
            if loaded > 1, seenParts.contains(partKey) { break }
            seenParts.insert(partKey)
            parts.append(part)

            guard nonEmpty(rule.nextContentUrl) != nil else { continue }
            for next in try analyzer.urls(rule.nextContentUrl) {
                let key = LegadoURLResolver.normalizedForComparison(next)
                // Dừng ở ranh giới chương: URL chương kế, hoặc bất kỳ chương nào khác của mục lục.
                guard !key.isEmpty, !visited.contains(key), key != stopKey, !session.tocStopKeys.contains(key) else { continue }
                visited.insert(key)
                queue.append(next)
            }
        }
        if head < queue.count {
            session.diagnostics.record(.info, "Nội dung vượt \(contentPageLimit) trang — dừng, dùng phần đã có")
        }

        let joined = parts.joined(separator: "\n")
        var processed = joined
        if nonEmpty(rule.replaceRegex) != nil, !trimmed(joined).isEmpty {
            let replaced = try session.analyzer(node: .string(joined), baseUrl: chapterUrl, src: joined).string(rule.replaceRegex)
            if trimmed(replaced).isEmpty {
                // Rule hỏng (regex/JS lỗi ⇒ rỗng) không được xoá trắng cả chương: giữ bản trước khi thay.
                session.diagnostics.record(.info, "replaceRegex cho kết quả rỗng — giữ nội dung trước khi thay")
            } else {
                processed = replaced
            }
        }
        return CollectedContent(html: processed, pageURL: firstPageURL)
    }

    /// URL chương kế của `chapterUrl`: mục lục vừa tải trong bộ nhớ, không có thì `ChapterStore` theo `bookId` +
    /// `chapterIndex` (chỉ khi dòng ở `chapterIndex` đúng là chương này). Dòng tiêu đề nhóm (tranh/video) bị bỏ qua.
    static func nextChapterURL(_ target: Target, chapterUrl: String, bookUrl: String, context: SourceRuntimeContext?) async -> String? {
        if !bookUrl.isEmpty,
           let next = LegadoTocURLCache.shared.nextURL(after: chapterUrl, index: context?.chapterIndex,
                                                       packageId: target.packageId, bookUrl: bookUrl) {
            return next
        }
        guard let bookId = nonEmpty(context?.bookId), let index = context?.chapterIndex, index >= 0 else { return nil }
        guard let rows = try? await ChapterStore.shared.fetchRange(bookId: bookId, startIndex: index, count: 4),
              let current = rows.first(where: { $0.index == index }), current.url == chapterUrl else { return nil }
        let next = rows.filter { $0.index > index && !$0.isSection }.min { $0.index < $1.index }
        return next?.url
    }

    /// URL đã chuẩn hoá của mọi chương **khác** chương đang tải: mục lục đệm trong bộ nhớ, không có thì đọc
    /// `ChapterStore` một lần theo `bookId` rồi đệm lại. Không có mục lục ⇒ tập rỗng (chỉ còn URL chương kế làm mốc).
    static func tocStopKeys(_ target: Target, chapterUrl: String, bookUrl: String, context: SourceRuntimeContext?) async -> Set<String> {
        var urls = bookUrl.isEmpty ? nil : LegadoTocURLCache.shared.urls(packageId: target.packageId, bookUrl: bookUrl)
        if urls == nil, let bookId = nonEmpty(context?.bookId),
           let rows = try? await ChapterStore.shared.fetchRange(bookId: bookId, startIndex: 0, count: tocStopFetchLimit),
           !rows.isEmpty {
            let list = rows.sorted { $0.index < $1.index }.map { $0.isSection ? "" : $0.url }
            urls = list
            if !bookUrl.isEmpty {
                LegadoTocURLCache.shared.store(list, packageId: target.packageId, bookUrl: bookUrl)
            }
        }
        let current = LegadoURLResolver.normalizedForComparison(chapterUrl)
        var keys = Set<String>()
        for url in urls ?? [] where !url.isEmpty {
            let key = LegadoURLResolver.normalizedForComparison(url)
            if !key.isEmpty, key != current { keys.insert(key) }
        }
        return keys
    }

    /// Trần số dòng mục lục đọc từ `ChapterStore` cho tập dừng (truyện dài nhất thường vài nghìn chương).
    static let tocStopFetchLimit = 20_000
}
