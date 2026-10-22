import Foundation

/// Chuỗi nghiệm thu của **một** nguồn: lối vào (tìm / khám phá / URL gỡ lỗi) → chi tiết → mục lục → nội dung chương
/// đầu (tranh: danh sách ảnh + ảnh đầu; video: server + nguồn phát — `LegadoCorpusProbe+Media`), mọi bước qua facade
/// `SourceRuntime.shared` để đo đúng đường app chạy thật. Mỗi bước có trần thời gian riêng
/// (`LegadoCorpusDeadline`), ghi thời gian + số mục, và dừng ở bước hỏng đầu tiên.
///
/// Ngữ cảnh truyện dùng `bookId` có namespace `corpus-runner:<packageId>` và cùng chuỗi `bookUrl` (= `link` của mục)
/// cho cả chi tiết/mục lục/nội dung: trạng thái truyện của runtime (khoá `packageId + bookUrl`, chỉ mục theo `bookId`)
/// nối được ba bước, và **không** bao giờ trùng id một cuốn sách thật trên kệ — bộ nghiệm thu không đụng trạng thái
/// truyện của người dùng. Runtime chỉ ghi trạng thái ra đĩa cho sách đã lên kệ, nên id này không sinh file.
///
/// Không giữ kết quả kiểu manager (không `Sendable`) qua ranh giới task: closure của mỗi bước rút ngay phần cần cho
/// bước sau thành struct `Sendable`. Không đọc/ghi nội dung chương ra ngoài — chỉ đếm ký tự.
final class LegadoCorpusProbe {
    // Trần của **bộ chạy**, rộng hơn timeout của engine (15 s/request + 1 lần thử lại, WebView 30 s + delay) để lỗi chậm
    // thật được engine báo trước (`timeout` kèm URL); trần ở đây chỉ chặn bước treo (vòng JS, chuỗi request dài).
    static let searchSeconds = 60
    static let exploreSeconds = 60
    static let detailSeconds = 60
    /// Mục lục có vòng `nextTocUrl` (tới 200 trang, có `concurrentRate`) bên trong facade nên trần rộng hơn.
    static let tocSeconds = 300
    /// Nội dung có vòng `nextContentUrl` (tới 30 trang).
    static let contentSeconds = 120
    static let bookIdPrefix = "corpus-runner:"

    /// Mục đầu tiên mở được của danh sách tìm/khám phá.
    struct BookRef: Sendable {
        let link: String
        let host: String?
        let name: String?
        let author: String?
    }

    struct ListOutput: Sendable {
        let count: Int
        let book: BookRef?
    }

    struct ChapterRef: Sendable {
        let total: Int
        let index: Int
        let title: String
        let url: String
    }

    typealias Step = LegadoCorpusReport.Step
    typealias StepFailure = LegadoCorpusErrorClassifier.StepFailure

    let candidate: LegadoCorpusCandidate
    private let startedAt = Date()
    private let bookId: String
    private var entry: LegadoCorpusEntry = .unavailable
    private var entryQuery = ""
    private var hints: [String] = []
    private var steps: [LegadoCorpusReport.StepRecord] = []
    private(set) var lastPassed: Step?
    private(set) var currentStep: Step = .search
    private var abandonedSteps = 0
    /// Run log của bước đang/vừa chạy (một log mỗi bước — bằng chứng cho kết luận "lỗi do ai").
    private(set) var stepLog: LegadoRunLog?
    /// Nguồn có `loginUrl` (HTTP 401/403 ⇒ cần đăng nhập).
    private(set) var hasLoginUrl = false
    /// Loại nguồn (đọc từ `source.json`); tranh/video đi bước media thay cho nội dung chữ.
    var kind: LegadoSourceKind = .text
    var mediaCheck: LegadoCorpusReport.MediaCheck?

    private init(candidate: LegadoCorpusCandidate) {
        self.candidate = candidate
        self.bookId = Self.bookIdPrefix + candidate.packageId
    }

    /// Không bao giờ ném: mọi lỗi thành `SourceResult`. Lượt chạy bị huỷ ⇒ `outcome == .cancelled`.
    static func run(_ candidate: LegadoCorpusCandidate, defaultKeyword: String) async -> LegadoCorpusReport.SourceResult {
        let probe = LegadoCorpusProbe(candidate: candidate)
        do {
            try await probe.execute(defaultKeyword: defaultKeyword)
            return probe.makeResult(outcome: .passed, classification: nil, judgement: nil)
        } catch {
            if error is CancellationError, Task.isCancelled {
                return probe.makeResult(outcome: .cancelled, classification: nil, judgement: nil)
            }
            return probe.makeResult(outcome: .failed, classification: LegadoCorpusErrorClassifier.classify(error),
                                    judgement: probe.judgement(for: error))
        }
    }

    // MARK: - Chuỗi

    private func execute(defaultKeyword: String) async throws {
        let source = try LegadoSourceStore.loadSource(localPath: candidate.localPath)
        hints = LegadoCorpusFeatureScan.hints(in: source)
        kind = source.kind
        hasLoginUrl = !source.loginUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        entry = LegadoCorpusEntry.resolve(
            checkKeyWord: source.ruleSearch.checkKeyWord,
            fallbackKeyword: defaultKeyword,
            hasSearchRules: source.hasSearchRules,
            hasExploreRules: source.hasExploreRules
        )
        entryQuery = entry.reportQuery
        currentStep = Self.firstStep(of: entry)

        guard SourceRuntime.shared.isLegado(localPath: candidate.localPath) else {
            throw StepFailure(failureClass: .invalidSource, message: "SourceRuntime không nhận thư mục này là nguồn Legado")
        }

        switch entry {
        case .keyword(let keyword):
            let book = try await search(keyword)
            try await continueFromBook(book)
        case .explore(let url):
            let book = try await explore(url)
            try await continueFromBook(book)
        case .catalogExplore:
            let book = try await catalogExplore()
            try await continueFromBook(book)
        case .bookURL(let url):
            try await continueFromBook(BookRef(link: url, host: nil, name: nil, author: nil))
        case .tocURL(let url):
            let chapter = try await toc(bookURL: url, book: nil)
            try await content(chapter, bookURL: url, book: nil)
        case .contentURL(let url):
            try await content(ChapterRef(total: 1, index: 0, title: "", url: url), bookURL: nil, book: nil)
        case .unavailable:
            throw StepFailure(failureClass: .invalidSource, message: "Nguồn không có rule tìm kiếm hay mục khám phá mở được",
                              isSourceDefect: true)
        }
    }

    private func continueFromBook(_ book: BookRef) async throws {
        try await detail(book)
        let chapter = try await toc(bookURL: book.link, book: book)
        try await content(chapter, bookURL: book.link, book: book)
    }

    // MARK: - Bước

    private func search(_ keyword: String) async throws -> BookRef {
        let path = candidate.localPath
        let downloadUrl = candidate.downloadUrl
        let config = candidate.configJson
        let output = try await measure(.search, seconds: Self.searchSeconds, operation: { () async throws -> ListOutput in
            let items = try await SourceRuntime.shared.search(
                localPath: path, downloadUrl: downloadUrl, query: keyword, page: 1, configJson: config
            )
            return LegadoCorpusProbe.firstBook(items)
        }, evaluate: { (count: $0.count, ok: $0.book != nil) })
        return try Self.requireBook(output, label: "Tìm kiếm")
    }

    private func explore(_ url: String) async throws -> BookRef {
        let path = candidate.localPath
        let downloadUrl = candidate.downloadUrl
        let config = candidate.configJson
        let output = try await measure(.explore, seconds: Self.exploreSeconds, operation: { () async throws -> ListOutput in
            let page = try await SourceRuntime.shared.executeCustomScript(
                localPath: path,
                downloadUrl: downloadUrl,
                scriptFileName: SourceRuntime.legadoExploreScriptName,
                input: url,
                page: 1,
                pageUrl: nil,
                configJson: config
            )
            return LegadoCorpusProbe.firstBook(page.results)
        }, evaluate: { (count: $0.count, ok: $0.book != nil) })
        return try Self.requireBook(output, label: "Khám phá")
    }

    /// Khám phá dạng JS: hỏi danh mục qua `home` rồi `genre`, mở mục đầu có script khám phá Legado.
    private func catalogExplore() async throws -> BookRef {
        let path = candidate.localPath
        let downloadUrl = candidate.downloadUrl
        let config = candidate.configJson
        let entryURL = try await measure(.explore, seconds: Self.exploreSeconds, operation: { () async throws -> String in
            var homeItems: [CategoryResult] = []
            do {
                homeItems = try await SourceRuntime.shared.home(localPath: path, downloadUrl: downloadUrl, configJson: config)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                homeItems = []
            }
            if let url = LegadoCorpusProbe.firstExploreInput(homeItems) { return url }
            let genreItems = try await SourceRuntime.shared.genre(localPath: path, downloadUrl: downloadUrl, configJson: config)
            return LegadoCorpusProbe.firstExploreInput(genreItems) ?? ""
        }, evaluate: { (count: $0.isEmpty ? 0 : 1, ok: !$0.isEmpty) })
        guard !entryURL.isEmpty else {
            throw StepFailure(failureClass: .noMatch, message: "Danh mục khám phá không có mục mở được")
        }
        entryQuery = LegadoCorpusErrorClassifier.redactURL(entryURL)
        return try await explore(entryURL)
    }

    private func detail(_ book: BookRef) async throws {
        let path = candidate.localPath
        let downloadUrl = candidate.downloadUrl
        let config = candidate.configJson
        let context = makeContext(bookURL: book.link, book: book, chapter: nil)
        _ = try await measure(.detail, seconds: Self.detailSeconds, operation: { () async throws -> Int in
            let result = try await SourceRuntime.shared.detail(
                localPath: path, downloadUrl: downloadUrl, url: book.link, host: book.host,
                configJson: config, context: context
            )
            return result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
        }, evaluate: { (count: $0, ok: true) })
    }

    private func toc(bookURL: String, book: BookRef?) async throws -> ChapterRef {
        let path = candidate.localPath
        let downloadUrl = candidate.downloadUrl
        let config = candidate.configJson
        let host = book?.host
        let context = makeContext(bookURL: bookURL, book: book, chapter: nil)
        let chapter = try await measure(.toc, seconds: Self.tocSeconds, operation: { () async throws -> ChapterRef in
            let chapters = try await SourceRuntime.shared.toc(
                localPath: path, downloadUrl: downloadUrl, url: bookURL, host: host,
                configJson: config, context: context
            )
            let index = chapters.firstIndex { row in
                !row.isSection && !row.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard let index else { return ChapterRef(total: chapters.count, index: 0, title: "", url: "") }
            return ChapterRef(total: chapters.count, index: index, title: chapters[index].name, url: chapters[index].url)
        }, evaluate: { (count: $0.total, ok: !$0.url.isEmpty) })
        guard !chapter.url.isEmpty else {
            let message = chapter.total == 0
                ? "Mục lục trả 0 chương"
                : "Mục lục có \(chapter.total) dòng nhưng không chương nào có URL"
            throw StepFailure(failureClass: .noMatch, message: message)
        }
        return chapter
    }

    private func content(_ chapter: ChapterRef, bookURL: String?, book: BookRef?) async throws {
        if kind.contentKind.isMedia {
            try await mediaContent(chapter, bookURL: bookURL, book: book)
            return
        }
        let path = candidate.localPath
        let downloadUrl = candidate.downloadUrl
        let config = candidate.configJson
        let host = book?.host
        let chapterURL = chapter.url
        let context = makeContext(bookURL: bookURL, book: book, chapter: chapter)
        let length = try await measure(.content, seconds: Self.contentSeconds, operation: { () async throws -> Int in
            let text = try await SourceRuntime.shared.chap(
                localPath: path, downloadUrl: downloadUrl, url: chapterURL, host: host,
                configJson: config, context: context
            )
            return text.trimmingCharacters(in: .whitespacesAndNewlines).count
        }, evaluate: { (count: $0, ok: $0 > 0) })
        guard length > 0 else {
            throw StepFailure(failureClass: .noMatch, message: "Nội dung chương rỗng")
        }
    }

    // MARK: - Đo

    /// Chạy một bước dưới trần thời gian, ghi `StepRecord`. Bước "không ok" (rỗng) vẫn trả giá trị để caller ném
    /// `noMatch` kèm câu cụ thể; lỗi thì ghi bước hỏng rồi ném tiếp. Mỗi bước một `LegadoRunLog` gắn qua task-local
    /// **bên trong** closure công việc (facade không có tham số log) — bằng chứng cho kết luận khi bước hỏng.
    func measure<T: Sendable>(
        _ step: Step,
        seconds: Int,
        operation: @escaping @Sendable () async throws -> T,
        evaluate: (T) -> (count: Int, ok: Bool)
    ) async throws -> T {
        currentStep = step
        let began = Date()
        let log = LegadoRunLog()
        stepLog = log
        do {
            let value = try await LegadoCorpusDeadline.run(seconds: seconds) { () async throws -> T in
                try await LegadoRunLog.$current.withValue(log) { try await operation() }
            }
            let verdict = evaluate(value)
            steps.append(.init(step: step, durationMs: Self.milliseconds(since: began), count: verdict.count, ok: verdict.ok))
            if verdict.ok { lastPassed = step }
            return value
        } catch {
            steps.append(.init(step: step, durationMs: Self.milliseconds(since: began), count: 0, ok: false))
            if error is LegadoCorpusDeadline.Exceeded { abandonedSteps += 1 }
            throw error
        }
    }

    func makeContext(bookURL: String?, book: BookRef?, chapter: ChapterRef?) -> SourceRuntimeContext {
        let title = chapter?.title ?? ""
        return SourceRuntimeContext(
            bookId: bookId,
            bookUrl: bookURL,
            bookName: book?.name,
            bookAuthor: book?.author,
            chapterTitle: title.isEmpty ? nil : title,
            chapterIndex: chapter?.index
        )
    }

    private func makeResult(
        outcome: LegadoCorpusReport.Outcome,
        classification: LegadoCorpusErrorClassifier.Classification?,
        judgement: LegadoFailureArbiter.Judgement?
    ) -> LegadoCorpusReport.SourceResult {
        LegadoCorpusReport.SourceResult(
            packageId: candidate.packageId,
            name: candidate.name,
            outcome: outcome,
            entry: entry.modeName,
            query: entryQuery,
            lastPassedStep: lastPassed,
            failedStep: outcome == .failed ? currentStep : nil,
            failureClass: classification?.failureClass,
            httpStatus: classification?.httpStatus,
            message: classification?.message,
            durationMs: Self.milliseconds(since: startedAt),
            steps: steps,
            unsupportedHints: hints,
            abandonedSteps: abandonedSteps,
            media: mediaCheck,
            verdict: judgement?.verdict,
            verdictReason: judgement?.reason
        )
    }

    // MARK: - Hàm thuần

    private static func firstStep(of entry: LegadoCorpusEntry) -> Step {
        switch entry {
        case .keyword, .unavailable: return .search
        case .explore, .catalogExplore: return .explore
        case .bookURL: return .detail
        case .tocURL: return .toc
        case .contentURL: return .content
        }
    }

    static func firstBook(_ items: [ExtensionItemResult]) -> ListOutput {
        let first = items.first { !$0.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first else { return ListOutput(count: items.count, book: nil) }
        return ListOutput(
            count: items.count,
            book: BookRef(
                link: first.link,
                host: first.host.isEmpty ? nil : first.host,
                name: first.name.isEmpty ? nil : first.name,
                author: first.author.isEmpty ? nil : first.author
            )
        )
    }

    static func firstExploreInput(_ items: [CategoryResult]) -> String? {
        items.first { item in
            item.script == SourceRuntime.legadoExploreScriptName
                && !item.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.input
    }

    private static func requireBook(_ output: ListOutput, label: String) throws -> BookRef {
        guard let book = output.book else {
            let message = output.count == 0
                ? "\(label) trả 0 mục"
                : "\(label) có \(output.count) mục nhưng không mục nào có link"
            throw StepFailure(failureClass: .noMatch, message: message)
        }
        return book
    }

    private static func milliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}
