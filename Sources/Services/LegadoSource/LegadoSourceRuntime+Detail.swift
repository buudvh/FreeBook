import Foundation
import SwiftSoup

/// Trang chi tiết truyện và mục lục.
extension LegadoSourceRuntime {

    // MARK: - Chi tiết

    public func bookInfo(
        source: LegadoBookSource,
        bookUrl: String,
        bookId: String?
    ) async throws -> NovelDetailResult {
        try requireTextSource(source)

        let stored = await storedVariables(source: source, bookId: bookId)
        let session = makeSession(
            source: source,
            baseUrl: source.bookSourceUrl,
            isJSONResponse: false,
            bookVariables: stored
        ) { scope in
            scope.bookUrl = bookUrl
        }

        let spec = request(
            rule: bookUrl,
            source: source,
            baseUrl: source.bookSourceUrl,
            session: session
        )
        try rejectIfWebViewRequired(spec)

        let response = try await LegadoHTTPClient.shared.send(spec)
        let context = LegadoRuleContext.from(response)
        let evaluator = LegadoRuleEvaluator(
            baseUrl: response.finalUrl,
            variables: session.variables,
            jsRuntime: session.jsRuntime,
            isJSONResponse: response.looksLikeJSON
        )

        let rule = source.ruleBookInfo
        // `init` chạy trước để thu hẹp phạm vi cho mọi rule còn lại.
        var scoped = context
        if let initRule = rule.initRule, !initRule.isEmpty {
            if let first = evaluator.elements(initRule, on: context).first {
                scoped = first
            }
        }

        let name = evaluator.string(rule.name, on: scoped) ?? ""
        let author = evaluator.string(rule.author, on: scoped) ?? ""
        let intro = evaluator.string(rule.intro, on: scoped) ?? ""
        let cover = evaluator.url(rule.coverUrl, on: scoped) ?? ""
        let kind = evaluator.string(rule.kind, on: scoped) ?? ""
        let wordCount = evaluator.string(rule.wordCount, on: scoped) ?? ""
        let lastChapter = evaluator.string(rule.lastChapter, on: scoped) ?? ""
        let updateTime = evaluator.string(rule.updateTime, on: scoped) ?? ""
        let tocUrl = evaluator.url(rule.tocUrl, on: scoped) ?? bookUrl

        // `tocUrl` phải sống qua các phiên: mục lục có thể ở URL khác trang chi tiết, mà `Book` của
        // FreeBook chỉ có `detailUrl` (và `detailUrl` không được đổi vì `bookId` băm từ nó).
        if let bookId {
            await LegadoBookStateStore.shared.save(
                packageId: source.packageId,
                bookId: bookId,
                bookVariables: session.variables.bookSnapshot,
                tocUrl: tocUrl
            )
        }

        return NovelDetailResult(
            name: name,
            author: author,
            cover: cover,
            description: intro,
            detail: buildDetailBlock(
                kind: kind,
                wordCount: wordCount,
                lastChapter: lastChapter,
                updateTime: updateTime,
                sourceName: source.bookSourceName
            ),
            host: source.bookSourceUrl,
            link: tocUrl,
            genres: [],
            suggests: [],
            comments: []
        )
    }

    /// `kind` / `wordCount` / `lastChapter` / `updateTime` không có chỗ riêng trong
    /// `NovelDetailResult`, nên gom vào `detail` — đúng chỗ FreeBook hiện dưới phần mô tả.
    private func buildDetailBlock(
        kind: String,
        wordCount: String,
        lastChapter: String,
        updateTime: String,
        sourceName: String
    ) -> String {
        var lines: [String] = []
        if !kind.isEmpty { lines.append("🏷️ Thể loại: " + kind.replacingOccurrences(of: "\n", with: ", ")) }
        if !wordCount.isEmpty { lines.append("📝 Số chữ: " + wordCount) }
        if !lastChapter.isEmpty { lines.append("🕒 Mới nhất: " + lastChapter) }
        if !updateTime.isEmpty { lines.append("📅 Cập nhật: " + updateTime) }
        lines.append("🌐 Nguồn: " + sourceName)
        return lines.joined(separator: "<br>")
    }

    // MARK: - Mục lục

    public func toc(
        source: LegadoBookSource,
        bookUrl: String,
        bookId: String?
    ) async throws -> [ChapterResult] {
        try requireTextSource(source)

        let stored = await storedVariables(source: source, bookId: bookId)
        var storedTocUrl: String?
        if let bookId, !bookId.isEmpty {
            storedTocUrl = await LegadoBookStateStore.shared.tocUrl(
                packageId: source.packageId,
                bookId: bookId
            )
        }
        let startUrl = (storedTocUrl?.isEmpty == false) ? storedTocUrl! : bookUrl

        let session = makeSession(
            source: source,
            baseUrl: source.bookSourceUrl,
            isJSONResponse: false,
            bookVariables: stored
        ) { scope in
            scope.bookUrl = bookUrl
            scope.bookTocUrl = startUrl
        }

        var chapters: [ChapterResult] = []
        var visited = Set<String>()
        var nextUrl: String? = startUrl
        var pageCount = 0
        let rule = source.ruleToc

        while let current = nextUrl, !current.isEmpty, pageCount < 200 {
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

            let items = evaluator.elements(rule.listRule, on: context)
            for item in items {
                let title = evaluator.string(rule.chapterName, on: item) ?? ""
                let url = evaluator.url(rule.chapterUrl, on: item) ?? ""
                guard !title.isEmpty || !url.isEmpty else { continue }

                // Dòng tên tập bị loại ngay: `Chapter` của FreeBook không có cờ `isVolume`, giữ lại
                // là mục lục có dòng rác và lệch số chương so với Legado.
                if let volumeRule = rule.isVolume, !volumeRule.isEmpty {
                    let flag = evaluator.string(volumeRule, on: item) ?? ""
                    if isTruthy(flag) { continue }
                }

                chapters.append(ChapterResult(
                    name: title.isEmpty ? url : title,
                    url: url,
                    host: source.bookSourceUrl
                ))
            }

            nextUrl = evaluator.url(rule.nextTocUrl, on: context)
            if let next = nextUrl, visited.contains(next) { break }
        }

        if rule.shouldReverse {
            chapters.reverse()
        }

        var seen = Set<String>()
        let deduplicated = chapters.filter { chapter in
            let key = chapter.url.isEmpty ? chapter.name : chapter.url
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        guard !deduplicated.isEmpty else {
            AppLogger.shared.log("❌ [Legado][\(source.bookSourceName)] mục lục rỗng sau \(pageCount) trang — rule chapterList: \(rule.chapterList?.prefix(120) ?? "nil")")
            throw LegadoRuntimeError.emptyResult("mục lục")
        }
        AppLogger.shared.log("📖 [Legado][\(source.bookSourceName)] mục lục: \(deduplicated.count) chương / \(pageCount) trang")

        if let bookId, session.variables.isDirty {
            await LegadoBookStateStore.shared.save(
                packageId: source.packageId,
                bookId: bookId,
                bookVariables: session.variables.bookSnapshot
            )
        }
        return deduplicated
    }

    internal func storedVariables(source: LegadoBookSource, bookId: String?) async -> [String: String] {
        guard let bookId, !bookId.isEmpty else { return [:] }
        return await LegadoBookStateStore.shared.variables(
            packageId: source.packageId,
            bookId: bookId
        )
    }

    internal func isTruthy(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !(value.isEmpty || value == "false" || value == "0" || value == "null")
    }
}
