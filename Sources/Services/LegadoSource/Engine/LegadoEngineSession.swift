import Foundation

/// Một phiên engine nguồn Legado = **một tác vụ** (một lượt tìm trong một nguồn, một lần lấy thông tin/mục lục, một
/// chương kèm vòng `nextContentUrl`). Phiên giữ HTTP client, runtime JS (tạo lười, nạp `jsLib` một lần), rate limiter
/// và kho cookie dùng chung của nguồn, ngữ cảnh `book`/`chapter`, biến JS `key`/`page`/`nextChapterUrl`.
///
/// **Luồng/thread**: mọi thứ chạy đồng bộ trên **một thread nền riêng** do `run` tạo (stack 8 MB) — JS gọi `java.ajax`
/// chặn thread này, không bao giờ chặn main. Không giữ phiên ra ngoài `body` của `run`.
///
/// **Huỷ**: `Task` gọi `run` bị huỷ ⇒ cờ huỷ bật, request HTTP/WebView/rate limiter/`Thread.sleep` đang chờ nhả trong
/// ~0,1 giây và `run` ném `CancellationError` (không bao giờ bọc thành lỗi khác). Vòng lặp JS thuần không ngắt được.
final class LegadoEngineSession {
    /// Khung "nội dung hiện hành" của đoạn JS đang chạy, cho `java.getString`/`setContent` (§6.4.2).
    struct RuleFrame {
        var content: LegadoContentNode
        var baseUrl: String
        var src: String?
    }

    let source: LegadoEngineSource
    let store: LegadoPersistentStore
    let cancellation: LegadoEngineCancellation
    let diagnostics: LegadoEngineDiagnostics
    /// Kho trong bộ nhớ theo nguồn: biến rule khi không có sách, `cache.putMemory`.
    let memory: LegadoSourceSessionStore
    let cookieJar: LegadoCookieJar
    let rateLimiter: LegadoRateLimiter?

    /// Sách mà JS thấy qua `book` và nơi `java.put`/`@put` ghi (§5.7). Luồng đổi theo **từng mục** danh sách.
    var book: LegadoBookContext?
    /// Chương mà JS thấy qua `chapter` (mục lục: mục đang dựng; nội dung: chương đang tải).
    var chapter: LegadoChapterContext?
    /// Biến JS `key` (từ khoá tìm kiếm thô, §3.4). `nil` ⇒ `undefined`.
    var key: String?
    /// Biến JS `page` (bắt đầu từ 1).
    var page: Int?
    /// Biến JS `nextChapterUrl` (nội dung, §6.2).
    var nextChapterUrl: String?
    /// Nhận `java.toast/longToast` (đã giới hạn ≤ 1 lần/giây). Service không được gọi toast UI trực tiếp: lớp ráp
    /// nối tự chuyển tiếp sang event center của app nếu muốn. Mặc định chỉ ghi log.
    var onToast: ((String) -> Void)?

    var ruleFrames: [RuleFrame] = []
    /// Đang tính header nguồn: header JS gọi `java.ajax` sẽ quay lại `buildRequest` → `sourceHeaders` (chặn đệ quy).
    var isComputingSourceHeaders = false
    private var httpStorage: LegadoHTTPClient?
    private var runtimeStorage: LegadoJSRuntime?
    private var lastToastDate: Date?

    init(source: LegadoEngineSource, book: LegadoBookContext?, chapter: LegadoChapterContext?,
         store: LegadoPersistentStore, cancellation: LegadoEngineCancellation) {
        self.source = source
        self.book = book
        self.chapter = chapter
        self.store = store
        self.cancellation = cancellation
        self.diagnostics = LegadoEngineDiagnostics(sourceName: source.name.isEmpty ? source.key : source.name)
        self.memory = LegadoSourceSessionStore.shared(forSourceKey: source.key)
        self.cookieJar = LegadoCookieJar.shared(forSourceKey: source.key, store: store)
        self.rateLimiter = LegadoRateLimiter.shared(forSourceKey: source.key, rate: source.concurrentRate)
    }

    // MARK: - Điểm vào

    /// Chạy `body` trên thread engine mới; trả kết quả về `async`. Huỷ `Task` ⇒ `CancellationError`.
    /// Mỗi lần gọi tốn một thread (stack 8 MB): lớp gọi phải tự giới hạn số nguồn chạy song song.
    /// `body` là `@Sendable` vì chạy **ngoài** actor của nơi gọi: không chạm state `@MainActor`, trả kết quả bằng giá trị.
    static func run<T>(source: LegadoEngineSource,
                       book: LegadoBookContext? = nil,
                       chapter: LegadoChapterContext? = nil,
                       store: LegadoPersistentStore = LegadoFileStateStore.shared,
                       _ body: @escaping @Sendable (LegadoEngineSession) throws -> T) async throws -> T {
        let cancellation = LegadoEngineCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let thread = Thread {
                    let session = LegadoEngineSession(source: source, book: book, chapter: chapter,
                                                      store: store, cancellation: cancellation)
                    let outcome: Result<T, Error>
                    do {
                        try cancellation.check()
                        let value = try body(session)
                        outcome = .success(value)
                    } catch {
                        outcome = .failure(cancellation.isCancelled ? CancellationError() : error)
                    }
                    session.close()
                    continuation.resume(with: outcome)
                }
                thread.name = "FreeBook.LegadoEngine"
                thread.stackSize = 8 << 20
                thread.qualityOfService = .userInitiated
                thread.start()
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func checkCancellation() throws {
        try cancellation.check()
    }

    /// Giải phóng tài nguyên của phiên (gọi tự động cuối `run`).
    func close() {
        httpStorage?.invalidate()
        httpStorage = nil
        runtimeStorage = nil
        ruleFrames.removeAll()
        cookieJar.flushIfNeeded()
    }

    // MARK: - Tài nguyên lười

    var http: LegadoHTTPClient {
        if let httpStorage { return httpStorage }
        let client = LegadoHTTPClient(cancellation: cancellation)
        httpStorage = client
        return client
    }

    /// Runtime JS của phiên; lần đầu truy cập nạp `jsLib` (§5.8).
    var runtime: LegadoJSRuntime {
        if let runtimeStorage { return runtimeStorage }
        let made = LegadoJSRuntime(session: self)
        runtimeStorage = made
        made.loadLibrary(source.jsLib)
        return made
    }

    /// URL nền mặc định: URL gốc của nguồn; nguồn có khoá không phải URL thì dùng nguyên khoá.
    var sourceBase: String {
        let base = source.baseURL
        return base.isEmpty ? source.key : base
    }

    // MARK: - Biến rule (§5.7)

    /// `java.put`/`@put`: có sách ⇒ kho của sách; không ⇒ kho phiên của nguồn. Giá trị luôn là chuỗi.
    func putRuleVariable(_ key: String, _ value: String) {
        if let book {
            book.setRuleVariable(value, forKey: key)
        } else {
            memory.setRuleVariable(value, forKey: key)
        }
    }

    /// `java.get(k)`/`@get:{k}`: kho sách → kho phiên của nguồn → `book.getVariable`; thiếu ⇒ `""`.
    func ruleVariable(_ key: String) -> String {
        if let value = book?.ruleVariable(key) { return value }
        if let value = memory.ruleVariable(key) { return value }
        if let book {
            let value = book.variable(key)
            if !value.isEmpty { return value }
        }
        return ""
    }

    // MARK: - Analyzer

    /// Analyzer trên phản hồi: nội dung JSON/HTML, URL nền = URL cuối, `src` = thân thô.
    func analyzer(response: LegadoHTTPResponse) -> LegadoRuleAnalyzer {
        LegadoRuleAnalyzer(session: self, content: response.content, baseUrl: response.finalURL, src: response.body)
    }

    /// Analyzer trên một chuỗi (HTML hoặc JSON).
    func analyzer(content text: String, baseUrl: String) -> LegadoRuleAnalyzer {
        analyzer(node: .string(text), baseUrl: baseUrl, src: text)
    }

    /// Analyzer trên một nội dung bất kỳ; chuỗi được phân tích một lần thành JSON/HTML.
    func analyzer(node: LegadoContentNode, baseUrl: String, src: String?) -> LegadoRuleAnalyzer {
        if case .string(let text) = node {
            return LegadoRuleAnalyzer(session: self, content: .from(body: text, baseUrl: baseUrl), baseUrl: baseUrl,
                                      src: src ?? text)
        }
        return LegadoRuleAnalyzer(session: self, content: node, baseUrl: baseUrl, src: src)
    }

    // MARK: - Khung JS

    var currentFrameBaseUrl: String? {
        ruleFrames.last?.baseUrl
    }

    /// Analyzer cho `java.getString(rule[, content])`: thiếu `content` ⇒ nội dung hiện hành của đoạn JS đang chạy.
    func frameAnalyzer(content: LegadoContentNode?) -> LegadoRuleAnalyzer {
        let frame = ruleFrames.last
        let base = frame?.baseUrl ?? sourceBase
        // Không truyền `src` của trang: nội dung khung có thể là một **mục**, khi đó `src` (thân trang) sẽ làm XPath/`##`
        // chạy trên cả trang thay vì trên mục.
        return analyzer(node: content ?? frame?.content ?? .string(""), baseUrl: base, src: nil)
    }

    /// `java.setContent(content[, baseUrl])`: đổi nội dung hiện hành của đoạn JS đang chạy.
    func setFrameContent(_ content: LegadoContentNode?, baseUrl: String?) {
        let base = baseUrl ?? ruleFrames.last?.baseUrl ?? sourceBase
        let frame = RuleFrame(content: content ?? .string(""), baseUrl: base, src: nil)
        if ruleFrames.isEmpty {
            ruleFrames.append(frame)
        } else {
            ruleFrames[ruleFrames.count - 1] = frame
        }
    }

    // MARK: - Log & toast

    func logFromSource(_ message: String) {
        let text = message.count > 2000 ? String(message.prefix(2000)) + "…" : message
        AppLogger.shared.log("[Legado \(source.name)] \(text)")
    }

    func emitToast(_ message: String) {
        logFromSource("toast: \(message)")
        let now = Date()
        if let last = lastToastDate, now.timeIntervalSince(last) < 1 { return }
        lastToastDate = now
        onToast?(message)
    }
}
