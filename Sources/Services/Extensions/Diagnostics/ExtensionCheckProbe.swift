import Foundation

/// Chuỗi Kiểm tra của **một** tiện ích JS: tầng tĩnh cho mọi khoá khai báo (`ExtensionScriptStaticCheck`), rồi chạy
/// thật **lần lượt** các khoá app có gọi, mỗi lời gọi qua `SourceRuntime.shared` / `ExtensionManager.shared` — đúng
/// đường app chạy.
///
/// - Lối vào (`+Entries`): `home` → `explore` → `genre` → `search`, chạy **độc lập** (một cái lỗi không dừng cái khác).
///   `home`/`genre` chạy thêm script phụ của mục đầu (dòng con). `search` thử tối đa `maxHistoryKeywords` từ của lịch
///   sử tìm kiếm, không ra thì thử tên truyện lấy từ lối vào khác.
/// - Truyện thử (`+Book`): mục của `search`, không có thì `home` → `explore` → `genre`; rồi `detail`, `page` → `toc` →
///   `chap` (chữ / danh sách ảnh + ảnh đầu / server) → `track`. Bước trước không cho dữ liệu ⇒ bước sau "bỏ qua".
/// - TTS: chỉ chạy `voice`; `tts` chỉ kiểm tĩnh để không đụng runtime TTS đang phát (`ExtTTSRuntime`).
///
/// Mỗi bước có trần thời gian (`LegadoCorpusDeadline`); closure công việc rút ngay phần cần thành struct `Sendable`
/// (không giữ kết quả kiểu manager qua ranh giới task). Không ghi gì vào thư viện. Mỗi thay đổi trạng thái gửi
/// `onUpdate` để màn thăm dò thấy tiến độ từng dòng.
final class ExtensionCheckProbe {
    typealias Row = ExtensionCheckReport.ScriptResult
    typealias Kind = ExtensionCheckReport.Kind

    static let listSeconds = 60
    static let detailSeconds = 60
    static let tocSeconds = 120
    static let contentSeconds = 120
    /// Danh sách ảnh + ảnh đầu, hoặc nguồn phát + 1 KB đầu.
    static let mediaSeconds = 180
    static let maxHistoryKeywords = 3

    struct BookRef: Sendable {
        let link: String
        let host: String?
        let name: String?
        /// Khoá script cho ra mục này (`search`, `home`…).
        let source: String
    }

    /// `count` = số mục của danh sách (với `explore`: số section).
    struct ListOutput: Sendable {
        let count: Int
        let book: BookRef?
    }

    /// Kết luận của một bước chạy xong không ném: đạt kèm tóm tắt, hoặc rỗng kèm câu lỗi.
    struct Check {
        let ok: Bool
        let text: String

        static func pass(_ summary: String) -> Check { Check(ok: true, text: summary) }
        static func empty(_ message: String) -> Check { Check(ok: false, text: message) }
    }

    let target: ExtensionCheckRunner.Target
    let kind: Kind
    let historyKeywords: [String]
    /// `metadata.source` — URL dự phòng cho nút "Mở link lỗi" của bước không có URL đầu vào.
    let sourceURL: String?
    var result: ExtensionCheckReport.ExtensionResult
    /// Mục mở được đầu tiên của từng lối vào, theo khoá script.
    var books: [String: BookRef] = [:]
    private let startedAt = Date()
    private let onUpdate: @Sendable (ExtensionCheckReport.ExtensionResult) async -> Void

    private init(
        target: ExtensionCheckRunner.Target,
        historyKeywords: [String],
        onUpdate: @escaping @Sendable (ExtensionCheckReport.ExtensionResult) async -> Void
    ) {
        let kind = Self.kind(of: target)
        self.target = target
        self.kind = kind
        self.historyKeywords = historyKeywords
        self.sourceURL = ExtensionManifestReader.source(localPath: target.localPath)
        self.onUpdate = onUpdate
        self.result = ExtensionCheckReport.ExtensionResult(
            packageId: target.packageId, name: target.name, kind: kind, state: .running, durationMs: 0, scripts: []
        )
    }

    /// Không bao giờ ném: lỗi ghi vào từng dòng. Lượt bị huỷ ⇒ `state == .cancelled`, dòng chưa xong thành `cancelled`.
    static func run(
        _ target: ExtensionCheckRunner.Target,
        historyKeywords: [String],
        onUpdate: @escaping @Sendable (ExtensionCheckReport.ExtensionResult) async -> Void
    ) async -> ExtensionCheckReport.ExtensionResult {
        let probe = ExtensionCheckProbe(target: target, historyKeywords: historyKeywords, onUpdate: onUpdate)
        do {
            try await probe.execute()
            probe.result.state = .finished
        } catch {
            // Chỉ `CancellationError` của lượt bị dừng lọt ra tới đây (`perform` nuốt mọi lỗi khác).
            probe.markUnfinished(as: .cancelled, message: "Đã dừng giữa chừng")
            probe.result.state = .cancelled
        }
        probe.result.currentStep = nil
        probe.result.durationMs = milliseconds(since: probe.startedAt)
        return probe.result
    }

    private func execute() async throws {
        let scan = ExtensionScriptStaticCheck.scan(localPath: target.localPath)
        result.manifestIssue = scan.manifestIssue
        result.scripts = scan.entries.map(makeRow)
        await publish()
        switch kind {
        case .text, .comic, .video:
            try await runEntries()
            try await runBookChain()
        case .tts:
            try await runVoice()
        case .other:
            break
        }
    }

    // MARK: - Dòng

    /// Khoá được chạy thật theo loại tiện ích; khoá khác chỉ kiểm tĩnh.
    private var runtimeKeys: Set<String> {
        switch kind {
        case .text, .comic: return ["home", "explore", "genre", "search", "detail", "page", "toc", "chap"]
        case .video: return ["home", "explore", "genre", "search", "detail", "page", "toc", "chap", "track"]
        case .tts: return ["voice"]
        case .other: return []
        }
    }

    private func makeRow(_ entry: ExtensionScriptStaticCheck.Entry) -> Row {
        var row = Row(id: entry.key, key: entry.key, fileName: entry.fileName, subtitle: nil,
                      group: Self.group(of: entry.key), outcome: .pending)
        if let issue = entry.issue {
            Self.markStaticFailure(&row, issue: issue)
        } else if !runtimeKeys.contains(entry.key) {
            row.outcome = .staticOnly
            row.summary = staticOnlyNote(for: entry.key)
        }
        return row
    }

    private func staticOnlyNote(for key: String) -> String {
        if key == "tts" { return "Chỉ kiểm tĩnh — không đọc thử để khỏi đụng TTS đang phát" }
        if key == "track" { return "Chỉ kiểm tĩnh — app chỉ gọi track với tiện ích video" }
        return "Chỉ kiểm tĩnh — app chưa gọi khoá này"
    }

    static func markStaticFailure(_ row: inout Row, issue: String) {
        row.outcome = .failed
        row.staticIssue = issue
        row.message = issue
        row.failureClass = .invalidSource
        row.verdict = .script
    }

    static func group(of key: String) -> ExtensionCheckReport.Group {
        switch key {
        case "home", "explore", "genre", "search": return .entry
        case "detail", "page", "toc", "chap", "track": return .book
        case "voice", "tts": return .voice
        default: return .other
        }
    }

    func row(_ id: String) -> Row? {
        result.scripts.first { $0.id == id }
    }

    /// Dòng có khai, tầng tĩnh đạt và chưa chạy.
    func isRunnable(_ id: String) -> Bool {
        row(id)?.outcome == .pending
    }

    func update(_ id: String, _ change: (inout Row) -> Void) {
        guard let index = result.scripts.firstIndex(where: { $0.id == id }) else { return }
        change(&result.scripts[index])
    }

    func insertRow(_ row: Row, after parentId: String) {
        let index = result.scripts.firstIndex { $0.id == parentId }.map { $0 + 1 } ?? result.scripts.count
        result.scripts.insert(row, at: index)
    }

    /// Dòng còn chờ trong `ids` ⇒ "bỏ qua" kèm lý do.
    func skipPending(_ ids: [String], reason: String) {
        for id in ids where isRunnable(id) {
            update(id) {
                $0.outcome = .skipped
                $0.message = reason
            }
        }
    }

    private func markUnfinished(as outcome: ExtensionCheckReport.Outcome, message: String) {
        for index in result.scripts.indices {
            let outcome = result.scripts[index].outcome
            guard outcome == .pending || outcome == .running else { continue }
            result.scripts[index].outcome = outcome
            result.scripts[index].message = message
        }
    }

    func publish() async {
        await onUpdate(result)
    }

    // MARK: - Chạy một bước

    /// Chạy một bước dưới trần thời gian và ghi vào dòng `id`. Trả giá trị khi đạt; `nil` khi lỗi hay rỗng (đã ghi lý
    /// do, kết luận và link lỗi — `SourceErrorLink.resolve` ngay trong `catch`, lúc lỗi còn mang dấu vết fetch). Chỉ ném
    /// `CancellationError` khi lượt bị dừng.
    func perform<T: Sendable>(
        _ id: String,
        seconds: Int,
        fallbackURL: String?,
        host: String? = nil,
        operation: @escaping @Sendable () async throws -> T,
        check: (T) -> Check
    ) async throws -> T? {
        try Task.checkCancellation()
        update(id) { $0.outcome = .running }
        result.currentStep = id
        await publish()
        let began = Date()
        do {
            let value = try await LegadoCorpusDeadline.run(seconds: seconds, operation)
            let verdict = check(value)
            let elapsed = Self.milliseconds(since: began)
            let link = verdict.ok ? nil : SourceErrorLink.resolve(from: nil, fallback: fallbackURL ?? sourceURL, host: host)
            update(id) { row in
                row.durationMs = elapsed
                if verdict.ok {
                    row.outcome = .passed
                    row.summary = verdict.text
                } else {
                    row.outcome = .failed
                    row.failureClass = .noMatch
                    row.verdict = .sourceOutdated
                    row.message = verdict.text
                    row.errorLink = link
                }
            }
            await publish()
            return verdict.ok ? value : nil
        } catch {
            if error is CancellationError, Task.isCancelled { throw error }
            let classification = LegadoCorpusErrorClassifier.classify(ExtensionLoadError.unwrapped(error))
            let verdict = ExtensionCheckVerdict.judge(error: error, classification: classification)
            let link = SourceErrorLink.resolve(from: error, fallbacks: [fallbackURL, sourceURL], host: host)
            let elapsed = Self.milliseconds(since: began)
            update(id) { row in
                row.outcome = .failed
                row.durationMs = elapsed
                row.failureClass = classification.failureClass
                row.verdict = verdict
                row.message = classification.message
                row.errorLink = link
            }
            await publish()
            return nil
        }
    }

    // MARK: - Hàm thuần

    static func kind(of target: ExtensionCheckRunner.Target) -> Kind {
        if target.type == ExtensionType.tts { return .tts }
        switch ExtensionContentKind.resolve(localPath: target.localPath) {
        case .text: return .text
        case .comic: return .comic
        case .video: return .video
        case .unsupported: return .other
        }
    }

    static func milliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
