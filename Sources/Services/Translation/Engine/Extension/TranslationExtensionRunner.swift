import Foundation
import JavaScriptCore

/// Chạy `translate.js` của tiện ích dịch.
///
/// - **Một `JSExecutor` mỗi lượt** (một chương / một câu): nạp script một lần, gọi `execute` cho từng lô, xong thì bỏ —
///   không giữ executor lâu dài (luật "mỗi tác vụ một executor").
/// - Các lô chạy **tuần tự**. Lô trả lệch số dòng ⇒ chia đôi, tới mức từng dòng (`max_length ≤ 0` = không chia gì ⇒
///   cả lô tính lỗi). Lô lỗi (mạng, `Response.error`, script hỏng) ⇒ giữ phần đã dịch được, dừng gọi tiếp, các dòng
///   còn lại tính là lỗi để caller lùi về QT — gọi tiếp khi đang bị giới hạn chỉ tốn thêm lượt.
/// - Lượt trùng đang chạy (Reader + TTS cùng một chương) gộp làm một (`TranslationExtensionInflight`). Bản dịch và lỗi
///   gần đây vào `TranslationExtensionLineCache` ngay trong lượt đó.
/// - Chỉ `CancellationError` được ném ra từ `translateLines`; lỗi khác nằm trong kết quả. Huỷ không phải lỗi.
/// - Không tự chạy trên main: hàm `nonisolated async`, script chặn thread đang chạy tới khi xong (`JSExecutor.callAsync`).
enum TranslationExtensionRunner {
    struct Job: Sendable {
        let packageId: String
        let bookId: String
        let from: String
        let to: String
        let source: TranslationExtensionSource

        init(packageId: String, bookId: String, from: String, to: String, source: TranslationExtensionSource) {
            self.packageId = packageId
            self.bookId = bookId
            self.from = from
            self.to = to
            self.source = source
        }

        /// Job theo bộ dịch đã tra; `nil` khi bộ dịch là QT.
        init?(engine: ResolvedTranslationEngine, bookId: String, source: TranslationExtensionSource) {
            guard let packageId = engine.selection.packageId else { return nil }
            self.init(packageId: packageId, bookId: bookId, from: engine.selection.from,
                      to: engine.selection.to, source: source)
        }
    }

    typealias Line = TranslationExtensionBatchPlanner.Line
    private typealias Cache = TranslationExtensionLineCache

    private struct MismatchError: LocalizedError {
        var errorDescription: String? { "Tiện ích trả lệch số dòng" }
    }

    // MARK: - Nhiều dòng (nội dung chương)

    /// Dịch các dòng (theo `ChapterTextLine.id`). Dòng không có chữ bị bỏ qua (không dịch, không tính lỗi).
    static func translateLines(_ lines: [Line], job: Job) async throws -> TranslationExtensionLineResult {
        try Task.checkCancellation()
        let candidates = lines.filter { TranslationExtensionBatchPlanner.needsTranslation($0.text) }
        let context: TranslationExtensionContext
        do {
            context = try TranslationExtensionContext.load(packageId: job.packageId)
        } catch {
            return failure(candidates, engineName: job.packageId, error: error)
        }
        let scope = Cache.Scope(context: context, bookId: job.bookId, from: job.from, to: job.to, source: job.source)

        var translations: [Int: String] = [:]
        var failed = Set<Int>()
        var firstError: String?
        var pending: [Line] = []
        for line in candidates {
            if let value = Cache.shared.lookup(line.text, scope: scope).value {
                translations[line.id] = value
            } else if let message = Cache.shared.recentFailure(for: line.text, scope: scope) {
                failed.insert(line.id)
                firstError = firstError ?? message
            } else {
                pending.append(line)
            }
        }
        guard !pending.isEmpty else {
            return TranslationExtensionLineResult(
                engineName: context.name, translations: translations, failedLineIds: failed, errorMessage: firstError,
                requestedLineCount: candidates.count, hadCallError: firstError != nil
            )
        }

        let key = scope.prefix + "|" + pending.map(\.text).joined(separator: "\n").md5()
        let texts = pending.map(\.text)
        let outcome = try await TranslationExtensionInflight.shared.run(key: key) {
            try await performBatches(texts, context: context, scope: scope, job: job)
        }
        for (index, line) in pending.enumerated() {
            if let text = outcome.texts[index], !text.isEmpty {
                translations[line.id] = text
            } else {
                failed.insert(line.id)
            }
        }
        return TranslationExtensionLineResult(
            engineName: context.name, translations: translations, failedLineIds: failed,
            errorMessage: outcome.errorMessage ?? firstError ?? (failed.isEmpty ? nil : "Tiện ích trả thiếu bản dịch"),
            requestedLineCount: candidates.count, hadCallError: outcome.hadCallError || firstError != nil
        )
    }

    // MARK: - Một đoạn (tên chương, Dịch thử)

    /// Dịch một đoạn chữ, ném lỗi khi tiện ích lỗi. Dùng cache theo dòng (khoá = cả đoạn), kể cả lỗi gần đây;
    /// `bypassCache` (ô Dịch thử) ⇒ luôn gọi script.
    static func translateText(_ text: String, job: Job, bypassCache: Bool = false) async throws -> String {
        try Task.checkCancellation()
        guard TranslationExtensionBatchPlanner.needsTranslation(text) else { return text }
        let context = try TranslationExtensionContext.load(packageId: job.packageId)
        let scope = Cache.Scope(context: context, bookId: job.bookId, from: job.from, to: job.to, source: job.source)
        let ticket = Cache.shared.ticket(bookId: job.bookId)
        if !bypassCache {
            if let value = Cache.shared.lookup(text, scope: scope).value { return value }
            if let message = Cache.shared.recentFailure(for: text, scope: scope) {
                throw ExtensionManagerError.sourceResponse(message: message)
            }
        }
        do {
            let executor = try context.makeExecutor(scriptKey: "translate")
            let output = try await call(executor, text: text, context: context, job: job)
            let translated = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty else {
                throw TranslationExtensionResultParser.ShapeError(detail: "Tiện ích dịch trả bản dịch rỗng")
            }
            Cache.shared.insert(translated, for: text, scope: scope, ticket: ticket)
            return translated
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            Cache.shared.recordFailure(TranslationExtensionResultParser.shortMessage(for: error), for: text,
                                       scope: scope, ticket: ticket)
            throw error
        }
    }

    // MARK: - Một lượt (đã gộp trùng)

    /// Gọi tiện ích cho các dòng chưa có trong cache, ghi kết quả (và lỗi) vào cache. Chạy trong `Task` riêng của
    /// `TranslationExtensionInflight`.
    private static func performBatches(
        _ texts: [String],
        context: TranslationExtensionContext,
        scope: Cache.Scope,
        job: Job
    ) async throws -> TranslationExtensionInflight.Outcome {
        let ticket = Cache.shared.ticket(bookId: job.bookId)
        let lines = texts.enumerated().map { Line(id: $0.offset, text: $0.element) }
        var outputs: [Int: String] = [:]
        var firstError: String?
        var hadCallError = false
        var requestCount = 0

        do {
            let executor = try context.makeExecutor(scriptKey: "translate")
            let batches = TranslationExtensionBatchPlanner.batches(
                lines, maxLines: context.maxLines, maxLength: context.maxLength, disablesSplitting: context.disablesSplitting
            )
            for batch in batches {
                do {
                    try await translateBatch(batch, executor: executor, context: context, job: job,
                                             outputs: &outputs, requestCount: &requestCount)
                } catch {
                    if error is CancellationError || Task.isCancelled { throw CancellationError() }
                    firstError = TranslationExtensionResultParser.shortMessage(for: error)
                    hadCallError = !(error is MismatchError)
                    AppLogger.shared.log("❌ [ExtTranslate] \(context.name): lô \(batch.count) dòng lỗi — \(firstError ?? "")")
                    if hadCallError { break }
                }
            }
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            firstError = TranslationExtensionResultParser.shortMessage(for: error)
            hadCallError = true
            AppLogger.shared.log("❌ [ExtTranslate] \(context.name): không nạp được translate.js — \(firstError ?? "")")
        }

        var results: [String?] = []
        results.reserveCapacity(lines.count)
        let failureMessage = firstError ?? "Tiện ích trả thiếu bản dịch"
        for line in lines {
            if let text = outputs[line.id], !text.isEmpty {
                Cache.shared.insert(text, for: line.text, scope: scope, ticket: ticket)
                results.append(text)
            } else {
                Cache.shared.recordFailure(failureMessage, for: line.text, scope: scope, ticket: ticket)
                results.append(nil)
            }
        }
        let failedCount = results.filter { $0 == nil }.count
        AppLogger.shared.log("🌐 [ExtTranslate] \(context.name): \(lines.count) dòng mới, \(requestCount) lần gọi, "
            + "\(failedCount) lỗi")
        return TranslationExtensionInflight.Outcome(
            texts: results,
            errorMessage: failedCount > 0 ? failureMessage : nil,
            hadCallError: hadCallError
        )
    }

    /// Gọi một lô; lệch dòng ⇒ chia đôi đệ quy (trừ khi tiện ích cấm chia lô). Ghi bản dịch vào `outputs` theo id
    /// dòng ngay khi có, nên lỗi ở nửa sau không làm mất nửa đầu.
    private static func translateBatch(
        _ batch: [Line],
        executor: JSExecutor,
        context: TranslationExtensionContext,
        job: Job,
        outputs: inout [Int: String],
        requestCount: inout Int
    ) async throws {
        try Task.checkCancellation()
        requestCount += 1
        let output = try await call(executor, text: TranslationExtensionBatchPlanner.joined(batch), context: context, job: job)
        if let parts = TranslationExtensionBatchPlanner.split(output, for: batch) {
            for (line, part) in zip(batch, parts) { outputs[line.id] = part }
            return
        }
        guard !context.disablesSplitting else { throw MismatchError() }
        let middle = batch.count / 2
        try await translateBatch(Array(batch[..<middle]), executor: executor, context: context, job: job,
                                 outputs: &outputs, requestCount: &requestCount)
        try await translateBatch(Array(batch[middle...]), executor: executor, context: context, job: job,
                                 outputs: &outputs, requestCount: &requestCount)
    }

    /// `execute(text, from, to, source, model, style)` — mọi tham số là chuỗi (hợp đồng).
    private static func call(
        _ executor: JSExecutor,
        text: String,
        context: TranslationExtensionContext,
        job: Job
    ) async throws -> String {
        let value = try await executor.callAsync(
            functionName: "execute",
            arguments: [text, job.from, job.to, job.source.rawValue, context.model, context.style]
        )
        try Task.checkCancellation()
        return try TranslationExtensionResultParser.translatedText(from: value)
    }

    private static func failure(_ candidates: [Line], engineName: String, error: Error) -> TranslationExtensionLineResult {
        TranslationExtensionLineResult(
            engineName: engineName, translations: [:], failedLineIds: Set(candidates.map(\.id)),
            errorMessage: TranslationExtensionResultParser.shortMessage(for: error),
            requestedLineCount: candidates.count, hadCallError: true
        )
    }
}
