import Foundation

/// Các luồng của nguồn Legado (spec §5) dựng trên engine `LegadoEngineSession`: tìm kiếm (`+Search`), khám phá
/// (`+Explore`), thông tin sách (`+Detail`), mục lục (`+Toc`), nội dung (`+Content`).
///
/// Trả **đúng các DTO** của tiện ích JS (`ExtensionItemResult`, `NovelDetailResult`, `ChapterResult`,
/// `CategoryResult`, `String`) để call site không phải phân nhánh. Nhận thẳng `Target` (nguồn đã nạp), nên bộ chạy
/// nghiệm thu gọi được mà không cần cài nguồn vào kho; `log` (tuỳ chọn) gom chẩn đoán của mọi phiên.
///
/// Mỗi lượt gọi = một hoặc vài phiên engine (mỗi phiên một thread nền). Trạng thái theo truyện đọc/ghi qua
/// `LegadoBookStateStore`: nạp trước phiên, áp thay đổi sau phiên — engine không tự ghi đĩa.
enum LegadoSourceRuntime {
    /// Một nguồn đã nạp, sẵn sàng chạy.
    struct Target: Sendable {
        let packageId: String
        let source: LegadoBookSource
        let engineSource: LegadoEngineSource

        init(packageId: String, source: LegadoBookSource) {
            self.packageId = packageId
            self.source = source
            self.engineSource = LegadoEngineSource(
                key: source.bookSourceUrl,
                name: source.bookSourceName,
                group: source.bookSourceGroup,
                type: source.bookSourceType,
                header: source.header,
                jsLib: source.jsLib,
                concurrentRate: source.concurrentRate,
                enabledCookieJar: source.enabledCookieJar,
                loginUrl: source.loginUrl,
                rawJSON: source.rawJSONString
            )
        }

        /// Nguồn đọc thẳng từ JSON (chưa cài): `packageId` theo công thức đóng băng của kho.
        init(source: LegadoBookSource) {
            self.init(packageId: LegadoSourceIdentity.packageId(forSourceUrl: source.bookSourceUrl), source: source)
        }
    }

    /// Một "sách tìm thấy" (spec §5.11) kèm kho biến của mục (§5.7: biến phải sống từ tìm kiếm tới nội dung).
    struct FoundBook: Sendable {
        var name: String
        var author: String
        var kind: String
        var wordCount: String
        var lastChapter: String
        var intro: String
        var coverUrl: String
        var bookUrl: String
        var variables: [String: String]
        var ruleVariables: [String: String]
        /// Chỉ có khi trang tìm kiếm rơi thẳng vào trang sách (§5.1.4) — đã chạy thông tin sách.
        var tocUrl: String?
    }

    /// Kết quả rule `ruleBookInfo` (spec §5.3) trên một trang sách.
    struct BookInfo: Sendable {
        var name: String
        var author: String
        var kind: String
        var wordCount: String
        var lastChapter: String
        var intro: String
        var coverUrl: String
        /// `""` = mục lục nằm ngay trên trang sách.
        var tocUrl: String
    }

    /// Thông tin sách đã ghép giá trị dự phòng (ngữ cảnh, trạng thái cũ) + trạng thái sau khi ghi.
    struct BookInfoResult: Sendable {
        let info: BookInfo
        let state: LegadoBookState
    }

    /// Giới hạn trang của vòng phân trang (spec §5.6, §5.1.1).
    static let tocPageLimit = 200
    static let contentPageLimit = 30
    static let explorePageLimit = 100

    // MARK: - Phiên

    /// Chạy một phiên engine; chép chẩn đoán vào `log` khi phiên kết thúc (kể cả khi ném lỗi). `log == nil` ⇒ dùng
    /// task-local `LegadoRunLog.current` (bộ nghiệm thu gọi qua facade) — đọc **ở đây**, trong ngữ cảnh async, trước khi
    /// engine sang thread riêng. Trong lúc phiên chạy, log được gắn với phiên để code luồng ghi đầu dò bộ chọn
    /// (`LegadoSelectorProbe.record(in:…)`).
    static func runSession<T>(
        _ target: Target,
        book: LegadoBookContext? = nil,
        chapter: LegadoChapterContext? = nil,
        log: LegadoRunLog?,
        _ body: @escaping @Sendable (LegadoEngineSession) throws -> T
    ) async throws -> T {
        let runLog = LegadoRunLog.resolve(log)
        return try await LegadoEngineSession.run(source: target.engineSource, book: book, chapter: chapter) { session in
            if let runLog { LegadoRunLog.sessions.bind(runLog, to: session) }
            defer {
                if let runLog {
                    LegadoRunLog.sessions.unbind(session)
                    runLog.absorb(session.diagnostics)
                }
            }
            return try body(session)
        }
    }

    /// Lỗi khi một bước ra **rỗng**: ưu tiên lý do thật nằm trong chẩn đoán (hàm chưa hỗ trợ ⇒ lỗi JS) rồi mới tới
    /// "rule khớp 0", để bộ nghiệm thu phân loại đúng.
    static func emptyResultError(_ session: LegadoEngineSession, _ what: String) -> LegadoEngineError {
        let diagnostics = session.diagnostics
        // Mục "bỏ qua, chỉ ghi vào bản sao" (`book.setReverseToc`…) không làm hỏng luồng — không tính là nguyên nhân.
        if let feature = diagnostics.unsupportedFeatures.first(where: { !$0.contains("bỏ qua") }) {
            return .unsupportedSyntax(feature)
        }
        if let script = diagnostics.entries.first(where: { $0.kind == .javaScript }) {
            return .javaScript(script.message)
        }
        return .noMatch(what)
    }

    // MARK: - Trạng thái theo truyện

    /// Chỉ ghi bền khi sách **đã lên kệ**: đã có file trạng thái, hoặc `ChapterStore` có mục lục của `bookId` (trang
    /// chi tiết chỉ lưu mục lục khi sách đã ở trên kệ). Sách chưa lên kệ mang UUID mới mỗi lần mở — chỉ giữ bộ nhớ.
    static func shouldPersist(bookId: String?) async -> Bool {
        guard let bookId = nonEmpty(bookId) else { return false }
        let store = LegadoBookStateStore.shared
        if store.isKnownSaved(bookId: bookId) { return true }
        let count = (try? await ChapterStore.shared.countChapters(bookId: bookId)) ?? 0
        guard count > 0 else { return false }
        store.markSaved(bookId: bookId)
        return true
    }

    /// Ngữ cảnh `book` cho JS từ trạng thái đã lưu + ngữ cảnh của call site.
    static func makeBookContext(
        _ target: Target,
        bookUrl: String,
        state: LegadoBookState,
        context: SourceRuntimeContext?
    ) -> LegadoBookContext {
        let info = state.info
        let book = LegadoBookContext(
            name: firstNonEmpty(info?.name, context?.bookName),
            author: firstNonEmpty(info?.author, context?.bookAuthor),
            kind: info?.kind ?? "",
            coverUrl: info?.coverUrl ?? "",
            intro: info?.intro ?? "",
            bookUrl: bookUrl,
            tocUrl: state.tocUrl ?? "",
            origin: target.source.bookSourceUrl,
            originName: target.source.bookSourceName,
            type: target.source.bookSourceType,
            latestChapterTitle: info?.latestChapterTitle ?? "",
            wordCount: info?.wordCount ?? "",
            durChapterIndex: context?.chapterIndex ?? 0,
            durChapterTitle: context?.chapterTitle ?? "",
            variables: state.variables,
            ruleVariables: state.ruleVariables
        )
        // `book.type` đã ghi ở lượt trước (spec §13.6) — JS đọc lại đúng giá trị đó.
        book.typeOverride = state.typeOverride
        return book
    }

    /// Ghi kho biến của các mục tìm kiếm/khám phá vào bộ nhớ (theo `packageId` + `bookUrl`) để thông tin/mục lục/nội
    /// dung của sách đó đọc lại được (§5.7). Mục không có biến thì bỏ qua.
    static func stashFoundBooks(_ books: [FoundBook], target: Target) {
        for book in books where !book.variables.isEmpty || !book.ruleVariables.isEmpty || book.tocUrl != nil {
            var delta = LegadoBookStateDelta(tocUrl: book.tocUrl)
            delta.variables = LegadoBookStateDelta.changes(from: [:], to: book.variables)
            delta.ruleVariables = LegadoBookStateDelta.changes(from: [:], to: book.ruleVariables)
            LegadoBookStateStore.shared.commit(delta, packageId: target.packageId, bookUrl: book.bookUrl,
                                               bookId: nil, persist: false)
        }
    }

    // MARK: - Chuyển sang DTO của app

    static func itemResult(_ book: FoundBook) -> ExtensionItemResult {
        ExtensionItemResult(
            name: book.name,
            author: book.author,
            description: book.intro.isEmpty ? book.lastChapter : book.intro,
            content: book.lastChapter,
            cover: displayCoverURL(book.coverUrl),
            link: book.bookUrl,
            host: origin(of: book.bookUrl)
        )
    }

    /// URL ảnh bìa cho bộ tải ảnh của app: bỏ khối option `,{"headers":…}` (bộ tải ảnh không hiểu, spec §5.3.4), mã hoá
    /// ký tự không phải ASCII; không phải `http(s)`/`data:` ⇒ `""`.
    static func displayCoverURL(_ raw: String) -> String {
        let url = LegadoURLResolver.splitOption(raw).url
        let lower = url.lowercased()
        if lower.hasPrefix("data:") { return url }
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return "" }
        return LegadoURLEncoder.encodeURL(url, encoding: .utf8)
    }

    /// `scheme://authority` của một URL (bỏ khối option); không phải `http(s)` ⇒ `""`.
    static func origin(of url: String) -> String {
        let base = LegadoURLResolver.splitOption(url).url
        guard LegadoURLResolver.hasHTTPScheme(base), let separator = base.range(of: "://") else { return "" }
        let rest = base[separator.upperBound...]
        let end = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
        let authority = rest[..<end]
        guard !authority.isEmpty else { return "" }
        return String(base[..<separator.lowerBound]) + "://" + String(authority)
    }

    // MARK: - Tiện ích chuỗi

    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            if let text = nonEmpty(value) { return text }
        }
        return ""
    }

    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mã JS của một trường "toàn JS" (`imageDecode`, `preUpdateJs`, `formatJs`): bỏ tiền tố `@js:` hoặc vỏ
    /// `<js>…</js>` nếu tác giả lỡ viết; còn lại giữ nguyên văn. Rỗng ⇒ `""`.
    static func scriptBody(_ raw: String) -> String {
        let text = trimmed(raw)
        let lower = text.lowercased()
        if lower.hasPrefix("@js:") {
            return trimmed(String(text.dropFirst(4)))
        }
        if lower.hasPrefix("<js>") {
            var code = String(text.dropFirst(4))
            if let close = code.range(of: "</js>", options: [.caseInsensitive, .backwards]) {
                code = String(code[..<close.lowerBound])
            }
            return trimmed(code)
        }
        return text
    }
}
