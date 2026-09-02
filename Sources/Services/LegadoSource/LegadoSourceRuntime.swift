import Foundation
import SwiftSoup

/// Chạy nguồn truyện JSON của Legado: tìm kiếm, khám phá, chi tiết, mục lục, nội dung.
///
/// Trả về **đúng các DTO mà extension VBook đang trả** (`ExtensionItemResult`, `NovelDetailResult`,
/// `ChapterResult`, `CategoryResult`), nên mọi tầng phía sau — View, `ChapterContentRepository`,
/// `DownloadManager`, TTS — không cần biết truyện đến từ runtime nào.
public final class LegadoSourceRuntime: @unchecked Sendable {
    public static let shared = LegadoSourceRuntime()

    private init() {}

    /// Bộ ba dùng cho một lượt bóc tách.
    internal struct Session {
        let variables: LegadoVariableBag
        let jsRuntime: LegadoJSRuntime
        let evaluator: LegadoRuleEvaluator
    }

    internal func makeSession(
        source: LegadoBookSource,
        baseUrl: String,
        isJSONResponse: Bool,
        bookVariables: [String: String] = [:],
        chapterVariables: [String: String] = [:],
        configure: ((inout LegadoJSScope) -> Void)? = nil
    ) -> Session {
        let bag = LegadoVariableBag(book: bookVariables, chapter: chapterVariables)
        var scope = LegadoJSScope.from(source: source, baseUrl: baseUrl)
        configure?(&scope)
        bag.bookName = scope.bookName
        bag.chapterTitle = scope.chapterTitle
        let runtime = LegadoJSRuntime(scope: scope, variables: bag)
        let evaluator = LegadoRuleEvaluator(
            baseUrl: baseUrl,
            variables: bag,
            jsRuntime: runtime,
            isJSONResponse: isJSONResponse
        )
        return Session(variables: bag, jsRuntime: runtime, evaluator: evaluator)
    }

    /// Dựng yêu cầu từ một rule URL, dùng JS runtime của session để nội suy.
    internal func request(
        rule: String,
        source: LegadoBookSource,
        baseUrl: String,
        session: Session,
        key: String? = nil,
        page: Int? = nil
    ) -> LegadoRequestSpec {
        let evaluator = session.evaluator
        let jsRuntime = session.jsRuntime
        let spec = LegadoUrlBuilder.build(
            rule: rule,
            baseUrl: baseUrl,
            key: key,
            page: page,
            sourceHeaders: jsRuntime.resolvedHeaderMap(),
            interpolate: { text in evaluator.interpolate(text, on: nil) },
            evaluateJS: { code, current in
                jsRuntime.evaluateToString(code, result: current)
            }
        )
        AppLogger.shared.log(
            "🌐 [Legado][\(source.bookSourceName)] \(spec.method) \(spec.url.prefix(220))"
                + (spec.body != nil ? " body=\(spec.body?.count ?? 0)B" : "")
                + (spec.charset != nil ? " charset=\(spec.charset ?? "")" : "")
        )
        return spec
    }

    // MARK: - Tìm kiếm

    public func search(
        source: LegadoBookSource,
        query: String,
        page: Int
    ) async throws -> [ExtensionItemResult] {
        guard let searchUrl = source.searchUrl, !searchUrl.isEmpty else {
            throw LegadoRuntimeError.missingRule("searchUrl")
        }
        try requireTextSource(source)

        let session = makeSession(
            source: source,
            baseUrl: source.bookSourceUrl,
            isJSONResponse: false
        ) { scope in
            scope.searchKey = query
            scope.page = page
        }

        let spec = request(
            rule: searchUrl,
            source: source,
            baseUrl: source.bookSourceUrl,
            session: session,
            key: query,
            page: page
        )
        try rejectIfWebViewRequired(spec)

        let response = try await LegadoHTTPClient.shared.send(spec)
        return parseList(
            response: response,
            source: source,
            rule: source.ruleSearch,
            session: session
        )
    }

    // MARK: - Khám phá

    public func exploreKinds(source: LegadoBookSource) async throws -> [CategoryResult] {
        guard let exploreUrl = source.exploreUrl, !exploreUrl.isEmpty else { return [] }
        try requireTextSource(source)

        let session = makeSession(
            source: source,
            baseUrl: source.bookSourceUrl,
            isJSONResponse: false
        )

        // `exploreUrl` có thể là `@js:`/`<js>` sinh ra danh sách; chạy trước rồi mới phân tích.
        var raw = exploreUrl
        let lower = raw.lowercased()
        if lower.hasPrefix("@js:") {
            raw = session.jsRuntime.evaluateToString(String(raw.dropFirst(4)), result: "") ?? ""
        } else if lower.hasPrefix("<js>") {
            let body = raw.dropFirst(4)
            let code = body.range(of: "</js>", options: .caseInsensitive)
                .map { String(body[body.startIndex..<$0.lowerBound]) } ?? String(body)
            raw = session.jsRuntime.evaluateToString(code, result: "") ?? ""
        }

        return LegadoExploreKind.parse(raw)
            .filter { $0.isSupported }
            .map { CategoryResult(title: $0.title, input: $0.url, script: "") }
    }

    public func explore(
        source: LegadoBookSource,
        input: String,
        page: Int
    ) async throws -> [ExtensionItemResult] {
        try requireTextSource(source)
        let session = makeSession(
            source: source,
            baseUrl: source.bookSourceUrl,
            isJSONResponse: false
        ) { scope in
            scope.page = page
        }

        let spec = request(
            rule: input,
            source: source,
            baseUrl: source.bookSourceUrl,
            session: session,
            page: page
        )
        try rejectIfWebViewRequired(spec)

        let response = try await LegadoHTTPClient.shared.send(spec)
        // `ruleExplore` trống thì Legado dùng `ruleSearch` — nhiều nguồn khai một bộ dùng cho cả hai.
        let rule = (source.ruleExplore.bookList ?? "").isEmpty && (source.ruleExplore.name ?? "").isEmpty
            ? source.ruleSearch
            : source.ruleExplore
        return parseList(response: response, source: source, rule: rule, session: session)
    }

    // MARK: - Bóc tách danh sách

    private func parseList(
        response: LegadoHTTPResponse,
        source: LegadoBookSource,
        rule: LegadoListRule,
        session: Session
    ) -> [ExtensionItemResult] {
        let context = LegadoRuleContext.from(response)
        let evaluator = LegadoRuleEvaluator(
            baseUrl: response.finalUrl,
            variables: session.variables,
            jsRuntime: session.jsRuntime,
            isJSONResponse: response.looksLikeJSON
        )

        let itemContexts: [LegadoRuleContext]
        if rule.isSingleItem {
            itemContexts = [context]
        } else {
            itemContexts = evaluator.elements(rule.listRule, on: context)
        }

        var results: [ExtensionItemResult] = []
        for item in itemContexts {
            let name = evaluator.string(rule.name, on: item) ?? ""
            let link = evaluator.url(rule.bookUrl, on: item) ?? ""
            guard !name.isEmpty || !link.isEmpty else { continue }

            let author = evaluator.string(rule.author, on: item) ?? ""
            let intro = evaluator.string(rule.intro, on: item) ?? ""
            let cover = evaluator.url(rule.coverUrl, on: item) ?? ""

            results.append(ExtensionItemResult(
                name: name.isEmpty ? link : name,
                author: author,
                description: intro,
                content: "",
                cover: cover,
                link: link,
                host: source.bookSourceUrl
            ))
        }

        if rule.isReversed {
            results.reverse()
        }
        AppLogger.shared.log(
            "📚 [Legado][\(source.bookSourceName)] danh sách: \(itemContexts.count) phần tử → "
                + "\(results.count) truyện"
                + (results.isEmpty ? " — kiểm tra rule bookList/name/bookUrl" : "")
        )
        return results
    }

    // MARK: - Kiểm tra phạm vi

    internal func requireTextSource(_ source: LegadoBookSource) throws {
        guard source.isTextSource else {
            throw LegadoRuntimeError.unsupported(.nonTextSource, source.bookSourceName)
        }
    }

    internal func rejectIfWebViewRequired(_ spec: LegadoRequestSpec) throws {
        guard spec.requiresWebView else { return }
        throw LegadoRuntimeError.unsupported(.webViewRule, spec.url)
    }
}
