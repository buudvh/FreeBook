import Foundation

/// Nội dung chương (spec §5.5) với phân trang `nextContentUrl` (§5.6).
extension LegadoSourceRuntime {
    struct ContentOutcome: Sendable {
        var text: String
        var chapterVariables: [String: String]
    }

    /// Văn bản thuần của chương ở `chapterUrl` (`ChapterResult.url` nguyên văn). Mọi trang `nextContentUrl` chạy chung
    /// một phiên (một runtime JS). URL dừng = URL chương kế trong mục lục (bộ nhớ, rồi `ChapterStore`), để rule kiểu
    /// "下一章" không kéo cả truyện vào một chương. Kết quả chưa qua `ChapterTextNormalizer` — pipeline chương của app
    /// tự chuẩn hoá. Rỗng ⇒ ném (không lưu bản rỗng).
    static func content(_ target: Target, chapterUrl: String, context: SourceRuntimeContext?, log: LegadoRunLog? = nil) async throws -> String {
        let bookId = context?.bookId
        let store = LegadoBookStateStore.shared
        let initial = store.state(packageId: target.packageId, bookUrl: context?.bookUrl, bookId: bookId)
        let bookUrl = nonEmpty(context?.bookUrl) ?? initial.bookUrl
        let nextURL = await nextChapterURL(target, chapterUrl: chapterUrl, bookUrl: bookUrl, context: context)
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
        let outcome: ContentOutcome = try await runSession(target, book: book, chapter: chapter, log: log) { session in
            session.nextChapterUrl = nextURL
            let text = try Self.runContent(session: session, target: target, chapterUrl: chapterUrl, stopURL: nextURL)
            guard !text.isEmpty else { throw Self.emptyResultError(session, "nội dung chương (content)") }
            return ContentOutcome(text: text, chapterVariables: chapter.variables)
        }

        var delta = LegadoBookStateDelta()
        delta.recordBook(book, initial: initial)
        delta.recordChapter(url: chapterUrl, initial: initialChapterVariables, current: outcome.chapterVariables)
        store.commit(delta, packageId: target.packageId, bookUrl: nonEmpty(bookUrl), bookId: bookId, persist: persist)
        return outcome.text
    }

    /// Thân phiên nội dung: vòng trang (spec §5.6) → nối `\n` → `replaceRegex` trên chuỗi đã nối, **trước** bước HTML →
    /// văn bản (§5.5.3, khuyến nghị U17) → `LegadoHTMLText.plainText` (§5.5.2).
    static func runContent(session: LegadoEngineSession, target: Target, chapterUrl: String, stopURL: String?) throws -> String {
        let rule = target.source.ruleContent
        let webJs = nonEmpty(rule.webJs)
        let stopKey = stopURL.map { LegadoURLResolver.normalizedForComparison($0) }
        var queue = [chapterUrl]
        var head = 0
        var visited: Set<String> = [LegadoURLResolver.normalizedForComparison(chapterUrl)]
        var seenParts: Set<String> = []
        var parts: [String] = []
        var loaded = 0
        while head < queue.count, loaded < contentPageLimit {
            let pageURL = queue[head]
            head += 1
            let response: LegadoHTTPResponse
            if loaded == 0 {
                response = try session.fetch(pageURL, webJs: webJs)
            } else {
                do {
                    response = try session.fetch(pageURL, webJs: webJs)
                } catch let error as LegadoEngineError {
                    session.diagnostics.record(.info, "Dừng phân trang nội dung: \(error.localizedDescription)")
                    break
                }
            }
            loaded += 1
            visited.insert(LegadoURLResolver.normalizedForComparison(response.finalURL))
            let analyzer = session.analyzer(response: response)
            let part = try analyzer.string(rule.content)
            let partKey = trimmed(part)
            // Trang lờ tham số trả lại đúng nội dung trước ⇒ dừng.
            if loaded > 1, seenParts.contains(partKey) { break }
            seenParts.insert(partKey)
            parts.append(part)

            guard nonEmpty(rule.nextContentUrl) != nil else { continue }
            for next in try analyzer.urls(rule.nextContentUrl) {
                let key = LegadoURLResolver.normalizedForComparison(next)
                guard !key.isEmpty, !visited.contains(key), key != stopKey else { continue }
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
        return LegadoHTMLText.plainText(fromHTML: processed)
    }

    /// URL chương kế của `chapterUrl`: mục lục vừa tải trong bộ nhớ, không có thì `ChapterStore` theo `bookId` +
    /// `chapterIndex` (chỉ khi dòng ở `chapterIndex` đúng là chương này).
    static func nextChapterURL(_ target: Target, chapterUrl: String, bookUrl: String, context: SourceRuntimeContext?) async -> String? {
        if !bookUrl.isEmpty,
           let next = LegadoTocURLCache.shared.nextURL(after: chapterUrl, index: context?.chapterIndex,
                                                       packageId: target.packageId, bookUrl: bookUrl) {
            return next
        }
        guard let bookId = nonEmpty(context?.bookId), let index = context?.chapterIndex, index >= 0 else { return nil }
        guard let rows = try? await ChapterStore.shared.fetchRange(bookId: bookId, startIndex: index, count: 2),
              let current = rows.first(where: { $0.index == index }), current.url == chapterUrl,
              let next = rows.first(where: { $0.index == index + 1 }) else { return nil }
        return next.url
    }
}
