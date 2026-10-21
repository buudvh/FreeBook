import Foundation

/// Bộ chạy của màn "Gỡ lỗi từng bước" (spec §12.3): từ bước bắt đầu theo ô nhập, đi tiếp tìm kiếm/khám phá → mục đầu
/// tiên → thông tin → mục lục → chương đầu tiên có URL; dừng ở bước đầu tiên ra rỗng hoặc lỗi.
///
/// Gọi **thẳng** các luồng `LegadoSourceRuntime` (không qua kho/`SourceRuntime`), nên chạy được cả nguồn đang tắt. Mỗi
/// bước dùng một `LegadoRunLog` riêng để tách vết request + log JS theo bước. Ngữ cảnh truyện dùng `bookId` có namespace
/// `debug-runner:<packageId>` và cùng chuỗi `bookUrl` cho mọi bước (như bộ nghiệm thu) — không đụng trạng thái truyện
/// thật trên kệ, không sinh file `legado_state/`. Trần thời gian mỗi bước giống bộ nghiệm thu.
///
/// Không gửi gì ra ngoài; kết quả chỉ đi lên View qua `onStep` (cùng `id` ⇒ thay bản trước của bước đó).
final class LegadoSourceDebugRunner {
    typealias StepHandler = @MainActor @Sendable (LegadoDebugStep) -> Void

    static let bookIdPrefix = "debug-runner:"
    static let listSeconds = 60
    static let detailSeconds = 60
    static let tocSeconds = 300
    static let contentSeconds = 120
    /// Số dòng log tối đa giữ cho một bước.
    static let maxLogLines = 120

    private struct BookRef: Sendable {
        let link: String
        let name: String?
        let author: String?
    }

    private struct ChapterRef: Sendable {
        let index: Int
        let title: String
        let url: String
    }

    private let target: LegadoSourceRuntime.Target
    private let bookId: String
    private let onStep: StepHandler
    private var nextId = 0

    private init(target: LegadoSourceRuntime.Target, onStep: @escaping StepHandler) {
        self.target = target
        // Mỗi lượt một `bookId` riêng: trạng thái truyện (biến, URL dừng của nội dung) của lượt trước không lọt sang.
        self.bookId = Self.bookIdPrefix + target.packageId + ":" + String(UUID().uuidString.prefix(8))
        self.onStep = onStep
    }

    /// Chạy một lượt. Trả thông báo lỗi khi không nạp được nguồn (chưa có bước nào), `nil` khi đã chạy.
    /// Huỷ task gọi hàm này ⇒ bước đang chạy thành "Đã dừng".
    static func run(packageId: String, input: LegadoDebugInput, onStep: @escaping StepHandler) async -> String? {
        let source: LegadoBookSource
        do {
            source = try LegadoSourceStore.loadSource(packageId: packageId)
        } catch {
            return "Không đọc được nguồn: \(error.localizedDescription)"
        }
        let runner = LegadoSourceDebugRunner(target: LegadoSourceRuntime.Target(packageId: packageId, source: source),
                                             onStep: onStep)
        await runner.execute(input)
        return nil
    }

    // MARK: - Chuỗi

    private func execute(_ input: LegadoDebugInput) async {
        let target = self.target
        let value = input.value
        switch input.mode {
        case .keyword:
            guard let book = await listStep(.search, input: value, operation: { log in
                try await LegadoSourceRuntime.search(target, query: value, page: 1, log: log)
            }) else { return }
            await continueFromBook(book)
        case .explore:
            let label = input.exploreTitle.isEmpty ? value : "\(input.exploreTitle)::\(value)"
            guard let book = await listStep(.explore, input: label, operation: { log in
                try await LegadoSourceRuntime.explorePage(target, url: value, page: 1, log: log).results
            }) else { return }
            await continueFromBook(book)
        case .bookURL:
            await continueFromBook(BookRef(link: value, name: nil, author: nil))
        case .toc:
            // Bắt đầu ở mục lục: ghi `tocUrl` = chính URL này vào trạng thái (bộ nhớ) để bước mục lục phân tích thẳng
            // trang đó thay vì chạy thông tin sách trước.
            LegadoBookStateStore.shared.commit(
                LegadoBookStateDelta(tocUrl: value), packageId: target.packageId, bookUrl: value, bookId: nil, persist: false
            )
            guard let chapter = await tocStep(bookURL: value, book: nil) else { return }
            await contentStep(chapter, bookURL: value, book: nil)
        case .content:
            await contentStep(ChapterRef(index: 0, title: "", url: value), bookURL: nil, book: nil)
        }
    }

    private func continueFromBook(_ book: BookRef) async {
        guard await detailStep(book) else { return }
        guard let chapter = await tocStep(bookURL: book.link, book: book) else { return }
        await contentStep(chapter, bookURL: book.link, book: book)
    }

    // MARK: - Bước

    private struct ListOutput: Sendable {
        let count: Int
        let book: BookRef?
        let fields: [LegadoDebugStep.Field]
    }

    private func listStep(
        _ kind: LegadoDebugStep.Kind,
        input: String,
        operation: @escaping @Sendable (LegadoRunLog) async throws -> [ExtensionItemResult]
    ) async -> BookRef? {
        let output: ListOutput? = await measure(kind, input: input, seconds: Self.listSeconds, operation: { log in
            let items = try await operation(log)
            let first = items.first { !$0.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let fields: [LegadoDebugStep.Field] = first.map { item in
                [
                    LegadoDebugStep.Field(name: "name", value: LegadoDebugStep.clip(item.name)),
                    LegadoDebugStep.Field(name: "author", value: LegadoDebugStep.clip(item.author)),
                    LegadoDebugStep.Field(name: "bookUrl", value: LegadoDebugStep.clip(item.link, limit: 400)),
                    LegadoDebugStep.Field(name: "coverUrl", value: LegadoDebugStep.clip(item.cover, limit: 400)),
                    LegadoDebugStep.Field(name: "lastChapter", value: LegadoDebugStep.clip(item.content)),
                    LegadoDebugStep.Field(name: "intro", value: LegadoDebugStep.clip(item.description))
                ]
            } ?? []
            let book = first.map { BookRef(link: $0.link, name: $0.name, author: $0.author) }
            return ListOutput(count: items.count, book: book, fields: fields)
        }, describe: { output, step in
            step.count = output.count
            step.fields = output.fields
            step.status = output.book == nil ? .empty : .passed
            if output.book == nil {
                step.errorMessage = output.count == 0 ? "Danh sách trả 0 mục" : "Có \(output.count) mục nhưng không mục nào có link"
            }
        })
        return output?.book
    }

    private func detailStep(_ book: BookRef) async -> Bool {
        let target = self.target
        let context = makeContext(bookURL: book.link, book: book, chapter: nil)
        let fields: [LegadoDebugStep.Field]? = await measure(.detail, input: book.link, seconds: Self.detailSeconds, operation: { log in
            let result = try await LegadoSourceRuntime.detail(target, bookUrl: book.link, context: context, log: log)
            return [
                LegadoDebugStep.Field(name: "name", value: LegadoDebugStep.clip(result.name)),
                LegadoDebugStep.Field(name: "author", value: LegadoDebugStep.clip(result.author)),
                LegadoDebugStep.Field(name: "kind", value: LegadoDebugStep.clip(result.genres.map(\.title).joined(separator: ", "))),
                LegadoDebugStep.Field(name: "coverUrl", value: LegadoDebugStep.clip(result.cover, limit: 400)),
                LegadoDebugStep.Field(name: "intro", value: LegadoDebugStep.clip(result.description)),
                LegadoDebugStep.Field(name: "khác", value: LegadoDebugStep.clip(result.detail))
            ]
        }, describe: { fields, step in
            step.count = 1
            step.fields = fields
            step.status = .passed
        })
        return fields != nil
    }

    private func tocStep(bookURL: String, book: BookRef?) async -> ChapterRef? {
        let target = self.target
        let context = makeContext(bookURL: bookURL, book: book, chapter: nil)
        let output: (total: Int, chapter: ChapterRef?, fields: [LegadoDebugStep.Field])? = await measure(
            .toc, input: bookURL, seconds: Self.tocSeconds, operation: { log in
                let chapters = try await LegadoSourceRuntime.toc(target, bookUrl: bookURL, context: context, log: log)
                let index = chapters.firstIndex { !$0.isSection && !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                var fields: [LegadoDebugStep.Field] = []
                var chapter: ChapterRef?
                if let index {
                    let first = chapters[index]
                    chapter = ChapterRef(index: index, title: first.name, url: first.url)
                    fields.append(LegadoDebugStep.Field(name: "chapterName", value: LegadoDebugStep.clip(first.name)))
                    fields.append(LegadoDebugStep.Field(name: "chapterUrl", value: LegadoDebugStep.clip(first.url, limit: 400)))
                }
                if let last = chapters.last, chapters.count > 1 {
                    fields.append(LegadoDebugStep.Field(name: "chương cuối", value: LegadoDebugStep.clip(last.name)))
                }
                return (chapters.count, chapter, fields)
            }, describe: { output, step in
                step.count = output.total
                step.fields = output.fields
                step.status = output.chapter == nil ? .empty : .passed
                if output.chapter == nil {
                    step.errorMessage = output.total == 0 ? "Mục lục trả 0 chương" : "Không chương nào có URL"
                }
            }
        )
        return output?.chapter
    }

    /// Kết quả bước nội dung: chữ ⇒ số ký tự + đầu chương; tranh ⇒ số ảnh + ảnh đầu; video ⇒ nguồn phát.
    private struct ContentOutput: Sendable {
        let count: Int
        let countText: String
        let fields: [LegadoDebugStep.Field]
        let emptyMessage: String
    }

    private func contentStep(_ chapter: ChapterRef, bookURL: String?, book: BookRef?) async {
        let target = self.target
        let context = makeContext(bookURL: bookURL, book: book, chapter: chapter)
        let chapterURL = chapter.url
        let _: ContentOutput? = await measure(.content, input: chapterURL, seconds: Self.contentSeconds, operation: { log in
            switch target.source.kind {
            case .comic:
                let pages = try await LegadoSourceRuntime.comicPages(target, chapterUrl: chapterURL, context: context, log: log)
                let fields = pages.first.map { [LegadoDebugStep.Field(name: "ảnh đầu", value: LegadoDebugStep.clip($0.link, limit: 400))] } ?? []
                return ContentOutput(count: pages.count, countText: "Số ảnh: \(pages.count)", fields: fields,
                                     emptyMessage: "Chương không có ảnh nào")
            case .video:
                let payload = LegadoVideoServerPayload(chapterUrl: chapterURL, context: context)
                let track = try await LegadoSourceRuntime.videoTrack(target, payload: payload, log: log)
                let fields = [
                    LegadoDebugStep.Field(name: "kiểu phát", value: "\(track.kind)"),
                    LegadoDebugStep.Field(name: "nguồn phát", value: LegadoDebugStep.clip(track.data, limit: 400))
                ]
                return ContentOutput(count: track.data.isEmpty ? 0 : 1, countText: "Có nguồn phát", fields: fields,
                                     emptyMessage: "Không có nguồn phát")
            default:
                let text = try await LegadoSourceRuntime.content(target, chapterUrl: chapterURL, context: context, log: log)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let fields = [LegadoDebugStep.Field(name: "đầu chương", value: LegadoDebugStep.clip(text))]
                return ContentOutput(count: text.count, countText: "Độ dài nội dung: \(text.count) ký tự", fields: fields,
                                     emptyMessage: "Nội dung chương rỗng")
            }
        }, describe: { output, step in
            step.count = output.count
            step.countText = output.countText
            step.fields = output.fields
            step.status = output.count == 0 ? .empty : .passed
            if output.count == 0 { step.errorMessage = output.emptyMessage }
        })
    }

    // MARK: - Đo một bước

    /// Phát thẻ "đang chạy", chạy `operation` dưới trần thời gian, rồi phát bản cuối. Trả giá trị khi bước **qua**,
    /// `nil` khi rỗng / lỗi / huỷ (chuỗi dừng ở đó).
    private func measure<T: Sendable>(
        _ kind: LegadoDebugStep.Kind,
        input: String,
        seconds: Int,
        operation: @escaping @Sendable (LegadoRunLog) async throws -> T,
        describe: (T, inout LegadoDebugStep) -> Void
    ) async -> T? {
        var step = LegadoDebugStep(id: nextId, kind: kind, status: .running, input: input)
        nextId += 1
        await onStep(step)
        let log = LegadoRunLog()
        let began = Date()
        do {
            let value = try await LegadoCorpusDeadline.run(seconds: seconds) { try await operation(log) }
            step.durationMs = Self.milliseconds(since: began)
            describe(value, &step)
            Self.attach(log, to: &step)
            if step.status == .empty {
                step.errorCategory = step.errorCategory ?? "noMatch"
                step.rule = ruleField(for: kind)
            }
            await onStep(step)
            return step.status == .passed ? value : nil
        } catch {
            step.durationMs = Self.milliseconds(since: began)
            Self.attach(log, to: &step)
            if error is CancellationError || Task.isCancelled {
                step.status = .cancelled
                step.errorMessage = "Đã dừng"
            } else if let exceeded = error as? LegadoCorpusDeadline.Exceeded {
                step.status = .failed
                step.errorCategory = "timeout"
                step.errorMessage = "Bước vượt trần \(exceeded.seconds) giây — đã bỏ chờ"
            } else {
                step.status = .failed
                step.errorCategory = LegadoRuntimeError.categoryName(of: error)
                step.errorMessage = error.localizedDescription
            }
            if step.status == .failed { step.rule = ruleField(for: kind) }
            await onStep(step)
            return nil
        }
    }

    /// Rule chính của bước (để người dùng thấy rule nào ra rỗng / lỗi).
    private func ruleField(for kind: LegadoDebugStep.Kind) -> LegadoDebugStep.Field {
        let source = target.source
        switch kind {
        case .search: return LegadoDebugStep.Field(name: "ruleSearch.bookList", value: source.ruleSearch.bookList)
        case .explore: return LegadoDebugStep.Field(name: "ruleExplore.bookList", value: source.effectiveExploreRule.bookList)
        case .detail: return LegadoDebugStep.Field(name: "ruleBookInfo.name", value: source.ruleBookInfo.name)
        case .toc: return LegadoDebugStep.Field(name: "ruleToc.chapterList", value: source.ruleToc.chapterList)
        case .content: return LegadoDebugStep.Field(name: "ruleContent.content", value: source.ruleContent.content)
        }
    }

    private static func attach(_ log: LegadoRunLog, to step: inout LegadoDebugStep) {
        step.requests = log.requests.map { record in
            LegadoDebugStep.Request(
                method: record.method,
                url: record.url,
                finalUrl: record.finalUrl,
                statusCode: record.statusCode,
                charset: record.charset,
                byteCount: record.byteCount,
                durationMs: record.durationMs,
                viaWebView: record.viaWebView,
                bodySnippet: record.bodySnippet,
                errorMessage: record.errorMessage
            )
        }
        step.logs = log.entries.prefix(maxLogLines).map { LegadoDebugStep.LogLine(kind: $0.kind, message: $0.message) }
        step.unsupported = log.unsupportedFeatures
    }

    private func makeContext(bookURL: String?, book: BookRef?, chapter: ChapterRef?) -> SourceRuntimeContext {
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

    private static func milliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}
