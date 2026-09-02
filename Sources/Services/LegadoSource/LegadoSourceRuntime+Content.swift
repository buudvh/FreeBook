import Foundation
import SwiftSoup

/// Nội dung chương, gồm vòng `nextContentUrl` và `replaceRegex` của nguồn.
extension LegadoSourceRuntime {

    public func content(
        source: LegadoBookSource,
        chapterUrl: String,
        chapterTitle: String?,
        chapterIndex: Int?,
        bookUrl: String?,
        bookId: String?
    ) async throws -> String {
        try requireTextSource(source)
        guard let contentRule = source.ruleContent.content, !contentRule.isEmpty else {
            throw LegadoRuntimeError.missingRule("ruleContent.content")
        }
        if !(source.ruleContent.imageDecode ?? "").isEmpty {
            throw LegadoRuntimeError.unsupported(.imageDecode, source.bookSourceName)
        }

        let bookVariables = await storedVariables(source: source, bookId: bookId)
        var chapterVariables: [String: String] = [:]
        if let bookId, let chapterIndex {
            chapterVariables = await LegadoBookStateStore.shared.chapterVariables(
                packageId: source.packageId,
                bookId: bookId,
                chapterIndex: chapterIndex
            )
        }

        let session = makeSession(
            source: source,
            baseUrl: source.bookSourceUrl,
            isJSONResponse: false,
            bookVariables: bookVariables,
            chapterVariables: chapterVariables
        ) { scope in
            scope.bookUrl = bookUrl
            scope.chapterUrl = chapterUrl
            scope.chapterTitle = chapterTitle
            scope.chapterIndex = chapterIndex
        }

        var pieces: [String] = []
        var visited = Set<String>()
        var nextUrl: String? = chapterUrl
        var pageCount = 0

        while let current = nextUrl, !current.isEmpty, pageCount < 50 {
            pageCount += 1
            guard !visited.contains(current) else { break }
            visited.insert(current)

            let spec = request(
                rule: current,
                source: source,
                baseUrl: source.bookSourceUrl,
                session: session
            )
            try rejectIfWebViewRequired(spec)

            let response = try await LegadoHTTPClient.shared.send(spec)
            try Task.checkCancellation()

            let context = LegadoRuleContext.from(response)
            let evaluator = LegadoRuleEvaluator(
                baseUrl: response.finalUrl,
                variables: session.variables,
                jsRuntime: session.jsRuntime,
                isJSONResponse: response.looksLikeJSON
            )

            if let piece = evaluator.string(contentRule, on: context), !piece.isEmpty {
                pieces.append(piece)
            }

            if let subRule = source.ruleContent.subContent, !subRule.isEmpty,
               let extra = evaluator.string(subRule, on: context), !extra.isEmpty {
                pieces.append(extra)
            }

            nextUrl = evaluator.url(source.ruleContent.nextContentUrl, on: context)
            if let next = nextUrl, visited.contains(next) { break }
        }

        guard !pieces.isEmpty else {
            AppLogger.shared.log("❌ [Legado][\(source.bookSourceName)] nội dung rỗng sau \(pageCount) trang — rule content: \(contentRule.prefix(120))")
            throw LegadoRuntimeError.emptyResult("nội dung chương")
        }

        var body = pieces.joined(separator: "\n")
        body = applySourceReplacements(body, rule: source.ruleContent.replaceRegex)
        AppLogger.shared.log("📄 [Legado][\(source.bookSourceName)] nội dung: \(body.count) ký tự / \(pageCount) trang")

        if let bookId, session.variables.isDirty {
            await LegadoBookStateStore.shared.save(
                packageId: source.packageId,
                bookId: bookId,
                bookVariables: session.variables.bookSnapshot,
                chapterIndex: chapterIndex,
                chapterVariables: session.variables.chapterSnapshot
            )
        }
        return body
    }

    /// `ContentRule.replaceRegex` là **phần của nguồn**, không phải của app, nên engine phải tự áp
    /// trước khi trả — nếu để tầng trên làm thì mọi nguồn dùng nó sẽ hiện nội dung lẫn rác.
    ///
    /// Cú pháp: nhiều dòng, mỗi dòng `##regex##replacement` (giống rule thường, không có phần selector).
    private func applySourceReplacements(_ body: String, rule: String?) -> String {
        guard let rule, !rule.isEmpty else { return body }
        var result = body

        for line in rule.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "##")
            // Dòng có thể viết `##regex##replacement` (bắt đầu bằng `##`) hoặc `regex##replacement`.
            let pattern: String
            let replacement: String
            if trimmed.hasPrefix("##") {
                pattern = parts.count > 1 ? parts[1] : ""
                replacement = parts.count > 2 ? parts[2] : ""
            } else {
                pattern = parts[0]
                replacement = parts.count > 1 ? parts[1] : ""
            }
            guard !pattern.isEmpty else { continue }
            result = LegadoRegexExtractor.applyReplacement(
                to: result,
                pattern: pattern,
                replacement: replacement,
                firstOnly: false
            )
        }
        return result
    }
}
