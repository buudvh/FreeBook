import Foundation

/// Lối vào của Kiểm tra tiện ích: `home` → `explore` → `genre` → `search`, mỗi cái chạy độc lập. Mục mở được đầu tiên
/// của từng lối vào ghi vào `books` để chọn truyện thử (`+Book`).
extension ExtensionCheckProbe {
    /// Mục đầu có script của danh mục `home`/`genre` (`CategoryResult` rút thành `Sendable`).
    struct CatalogOutput: Sendable {
        let count: Int
        let firstTitle: String
        let firstInput: String
        let firstScript: String?
    }

    struct SearchOutput: Sendable {
        let keyword: String?
        let list: ListOutput
    }

    func runEntries() async throws {
        try await runCatalog("home")
        try await runExplore()
        try await runCatalog("genre")
        try await runSearch()
    }

    // MARK: - home / genre

    /// Danh mục rồi script phụ của mục đầu có script — dòng con `<khoá>.item` ngay dưới khoá cha, chạy như app mở tab
    /// (`executeCustomScript(input, trang 1)`).
    private func runCatalog(_ key: String) async throws {
        guard isRunnable(key) else { return }
        let path = target.localPath
        let downloadUrl = target.downloadUrl
        let config = target.configJson
        let isHome = key == "home"
        let output = try await perform(key, seconds: Self.listSeconds, fallbackURL: sourceURL, operation: { () async throws -> CatalogOutput in
            let items: [CategoryResult]
            if isHome {
                items = try await SourceRuntime.shared.home(localPath: path, downloadUrl: downloadUrl, configJson: config)
            } else {
                items = try await SourceRuntime.shared.genre(localPath: path, downloadUrl: downloadUrl, configJson: config)
            }
            let first = items.first { ExtensionCheckProbe.nonEmpty($0.script) != nil }
            return CatalogOutput(count: items.count, firstTitle: first?.title ?? "", firstInput: first?.input ?? "",
                                 firstScript: ExtensionCheckProbe.nonEmpty(first?.script))
        }, check: { output in
            guard output.count > 0 else { return .empty(isHome ? "Trang chủ trả 0 tab" : "Thể loại trả 0 mục") }
            let unit = isHome ? "tab" : "mục"
            return .pass(output.firstScript == nil ? "\(output.count) \(unit) (không mục nào có script)" : "\(output.count) \(unit)")
        })
        guard let output, let script = output.firstScript else { return }

        let subId = key + ".item"
        var sub = Row(id: subId, key: key, fileName: script, subtitle: Self.nonEmpty(output.firstTitle) ?? "mục đầu",
                      group: .entry, outcome: .pending)
        if let issue = ExtensionScriptStaticCheck.fileIssue(script, localPath: path) {
            Self.markStaticFailure(&sub, issue: issue)
        }
        insertRow(sub, after: key)
        await publish()
        guard isRunnable(subId) else { return }

        let input = output.firstInput
        let list = try await perform(subId, seconds: Self.listSeconds, fallbackURL: input, operation: { () async throws -> ListOutput in
            let page = try await SourceRuntime.shared.executeCustomScript(
                localPath: path, downloadUrl: downloadUrl, scriptFileName: script, input: input, page: 1, pageUrl: nil,
                configJson: config
            )
            return ExtensionCheckProbe.firstBook(page.results, source: key)
        }, check: Self.listCheck)
        if let book = list?.book {
            books[key] = book
        }
    }

    // MARK: - explore

    private func runExplore() async throws {
        guard isRunnable("explore") else { return }
        let path = target.localPath
        let downloadUrl = target.downloadUrl
        let config = target.configJson
        let output = try await perform("explore", seconds: Self.listSeconds, fallbackURL: sourceURL, operation: { () async throws -> ListOutput in
            let sections = try await ExtensionManager.shared.explore(localPath: path, downloadUrl: downloadUrl, configJson: config)
            return ExtensionCheckProbe.firstExploreBook(sections)
        }, check: { output in
            guard output.count > 0 else { return .empty("Khám phá trả 0 section") }
            return .pass(output.book == nil ? "\(output.count) section (không mục nào mở chi tiết)" : "\(output.count) section")
        })
        if let book = output?.book {
            books["explore"] = book
        }
    }

    // MARK: - search

    /// Thử lần lượt từng từ khoá trong **một** bước: từ đầu tiên ra mục có link ⇒ đạt. Một lần gọi ném lỗi ⇒ dừng và
    /// báo lỗi đó (lỗi thật, không phải "không có kết quả").
    private func runSearch() async throws {
        guard isRunnable("search") else { return }
        let keywords = searchKeywords()
        guard !keywords.isEmpty else {
            skipPending(["search"], reason: "Không có từ khoá để thử: lịch sử tìm kiếm trống và lối vào khác không ra truyện")
            await publish()
            return
        }
        let path = target.localPath
        let downloadUrl = target.downloadUrl
        let config = target.configJson
        let quoted = keywords.map { "«\($0)»" }.joined(separator: ", ")
        let output = try await perform("search", seconds: Self.listSeconds * keywords.count, fallbackURL: sourceURL, operation: { () async throws -> SearchOutput in
            for keyword in keywords {
                let items = try await SourceRuntime.shared.search(
                    localPath: path, downloadUrl: downloadUrl, query: keyword, page: 1, configJson: config
                )
                let list = ExtensionCheckProbe.firstBook(items, source: "search")
                if list.book != nil { return SearchOutput(keyword: keyword, list: list) }
            }
            return SearchOutput(keyword: nil, list: ListOutput(count: 0, book: nil))
        }, check: { output in
            guard let keyword = output.keyword else {
                return .empty("Tìm \(keywords.count) từ đều không ra mục nào: \(quoted)")
            }
            return .pass("\(output.list.count) mục · từ «\(keyword)»")
        })
        if let output, let book = output.list.book {
            books["search"] = book
            result.keyword = output.keyword
        }
    }

    /// Tối đa `maxHistoryKeywords` từ gần nhất của lịch sử, rồi tên truyện của lối vào khác (đúng ngôn ngữ nguồn).
    func searchKeywords() -> [String] {
        var keywords: [String] = []
        for keyword in historyKeywords.prefix(Self.maxHistoryKeywords) where !keywords.contains(keyword) {
            keywords.append(keyword)
        }
        for source in ["home", "explore", "genre"] {
            guard let name = Self.nonEmpty(books[source]?.name) else { continue }
            if !keywords.contains(name) { keywords.append(name) }
            break
        }
        return keywords
    }

    // MARK: - Hàm thuần

    static func listCheck(_ output: ListOutput) -> Check {
        if output.book != nil { return .pass("\(output.count) mục") }
        return .empty(output.count == 0 ? "Trả 0 mục" : "Có \(output.count) mục nhưng không mục nào có link")
    }

    static func firstBook(_ items: [ExtensionItemResult], source: String) -> ListOutput {
        guard let first = items.first(where: { nonEmpty($0.link) != nil }) else {
            return ListOutput(count: items.count, book: nil)
        }
        let book = BookRef(link: first.link, host: nonEmpty(first.host), name: nonEmpty(first.name), source: source)
        return ListOutput(count: items.count, book: book)
    }

    /// Item mở chi tiết đầu tiên, như `ExploreSectionsView.handleTap`: không action ⇒ `link`; action `detail` ⇒ `input`
    /// (rỗng thì `link`); action `list`/lạ ⇒ bỏ qua.
    static func firstExploreBook(_ sections: [ExploreSection]) -> ListOutput {
        for section in sections {
            for item in section.items {
                let url: String?
                switch item.action?.kind {
                case nil: url = nonEmpty(item.link)
                case .detail?: url = nonEmpty(item.action?.input) ?? nonEmpty(item.link)
                case .list?, .unsupported?: url = nil
                }
                guard let url else { continue }
                let book = BookRef(link: url, host: nonEmpty(item.host), name: nonEmpty(item.name), source: "explore")
                return ListOutput(count: sections.count, book: book)
            }
        }
        return ListOutput(count: sections.count, book: nil)
    }
}
