import Foundation

/// Khám phá (spec §5.2): danh sách mục từ `exploreUrl` và một trang của một mục.
extension LegadoSourceRuntime {
    /// Nhớ `bookUrl` đã thấy ở các trang trước của từng mục khám phá: URL không có số trang trả lại trang 1 mãi, nên
    /// trang không có sách mới ⇒ hết trang (spec §5.1.1 bước 5).
    final class ExplorePageTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String: Set<String>] = [:]
        private var order: [String] = []
        private static let capacity = 32

        /// `true` khi trang có ít nhất một `bookUrl` chưa gặp. Trang 1 bắt đầu lại từ đầu.
        func record(key: String, page: Int, urls: [String]) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            var known = page <= 1 ? Set<String>() : (seen[key] ?? [])
            let before = known.count
            known.formUnion(urls)
            seen[key] = known
            order.removeAll { $0 == key }
            order.append(key)
            while order.count > Self.capacity {
                seen.removeValue(forKey: order.removeFirst())
            }
            return known.count > before
        }
    }

    static let explorePages = ExplorePageTracker()

    /// Mục khám phá bấm được → `CategoryResult` (`input` = rule URL nguyên văn của mục, `script` = `scriptName`). Tiêu đề
    /// nhóm bị loại; tiêu đề trùng nhau được thêm tên nhóm phía trước để phân biệt; trùng `id` bị bỏ (ForEach cần id
    /// duy nhất). `exploreUrl` rỗng ⇒ `[]`.
    static func exploreCategories(_ target: Target, scriptName: String, log: LegadoRunLog? = nil) async throws -> [CategoryResult] {
        if LegadoQuickSearch.applies(to: target.source) {
            return exploreCategories(from: LegadoQuickSearch.entries(), scriptName: scriptName)
        }
        let exploreUrl = target.source.exploreUrl
        guard nonEmpty(exploreUrl) != nil else { return [] }
        let items: [LegadoEngineExploreItem] = try await runSession(target, log: log) { session in
            let entries = try session.exploreItems(exploreUrl)
            if !entries.contains(where: { !$0.isGroupHeader }), Self.hasHardFailure(session) {
                throw Self.emptyResultError(session, "exploreUrl")
            }
            return entries
        }
        // Ánh xạ dùng chung với Khám phá động (`+ExploreControls`).
        return exploreCategories(from: items, scriptName: scriptName)
    }

    /// Một trang của mục khám phá `url` (spec §5.2.3): dựng request với `page`, không có `key` (biến `key` = rỗng);
    /// rule danh sách = `ruleExplore` thừa kế từng trường từ `ruleSearch` (§5.2.4). `nextPage` = `"\(page + 1)"` khi
    /// trang có sách **mới**, URL có chỗ cắm số trang và chưa quá `explorePageLimit`; ngược lại `nil`.
    static func explorePage(_ target: Target, url: String, page: Int, log: LegadoRunLog? = nil) async throws -> (results: [ExtensionItemResult], nextPage: String?) {
        let pageNumber = max(1, page)
        let rule = target.source.effectiveExploreRule
        let books: [FoundBook] = try await runSession(target, log: log) { session in
            session.key = ""
            session.page = pageNumber
            let response = try session.fetch(url, key: "", page: pageNumber)
            let analyzer = session.analyzer(response: response)
            let extracted = try Self.extractBooksCounting(session: session, analyzer: analyzer, rule: rule)
            let found = extracted.books
            if found.isEmpty {
                LegadoSelectorProbe.record(in: session, field: "bookList", rule: rule.bookList, response: response,
                                           matchedElements: extracted.matched)
            }
            if found.isEmpty, Self.hasHardFailure(session) {
                throw Self.emptyResultError(session, "bookList")
            }
            return found
        }
        stashFoundBooks(books, target: target)
        LegadoCoverDecoder.shared.register(rawCoverURLs: books.map { $0.coverUrl }, target: target)
        let trackerKey = LegadoBookStateStore.memoryKey(packageId: target.packageId, bookUrl: url)
        let hasNewBooks = explorePages.record(key: trackerKey, page: pageNumber, urls: books.map { $0.bookUrl })
        let hasNext = hasNewBooks && pageNumber < explorePageLimit && hasPagePlaceholder(url)
        return (books.map { itemResult($0) }, hasNext ? String(pageNumber + 1) : nil)
    }

    /// URL mục có chỗ cắm số trang: `{{…page…}}`, URL do JS sinh có nhắc `page`, hoặc danh sách trang `<a,b,…>` (§3.5).
    static func hasPagePlaceholder(_ url: String) -> Bool {
        if url.range(of: #"\{\{[^}]*page"#, options: .regularExpression) != nil { return true }
        let lower = url.lowercased()
        let isScript = lower.hasPrefix("@js:") || lower.contains("<js>")
        if isScript { return lower.contains("page") }
        return url.range(of: #"<[^<>]*,[^<>]*>"#, options: .regularExpression) != nil
    }
}
