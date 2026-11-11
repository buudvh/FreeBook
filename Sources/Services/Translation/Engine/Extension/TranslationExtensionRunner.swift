import Foundation
import JavaScriptCore

/// Chạy `translate.js` của tiện ích dịch.
///
/// - **Một `JSExecutor` mỗi lượt** (một chương / một câu): nạp script một lần, gọi `execute` cho từng lô, xong thì bỏ —
///   không giữ executor lâu dài (luật "mỗi tác vụ một executor").
/// - Các lô chạy **tuần tự**. Lô trả lệch số dòng ⇒ chia đôi, tới mức từng dòng. Lô lỗi (mạng, `Response.error`,
///   script hỏng) ⇒ dừng gọi tiếp, các dòng còn lại tính là lỗi để caller lùi về QT — gọi tiếp khi đang bị giới hạn
///   chỉ tốn thêm lượt.
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
        let scope = TranslationExtensionLineCache.Scope(
            context: context, bookId: job.bookId, from: job.from, to: job.to, source: job.source
        )

        var translations: [Int: String] = [:]
        var pending: [Line] = []
        var tickets: [Int: UInt64] = [:]
        for line in candidates {
            let cached = TranslationExtensionLineCache.shared.lookup(line.text, scope: scope)
            if let value = cached.value {
                translations[line.id] = value
            } else {
                pending.append(line)
                tickets[line.id] = cached.ticket
            }
        }
        guard !pending.isEmpty else {
            return TranslationExtensionLineResult(engineName: context.name, translations: translations,
                                                  failedLineIds: [], errorMessage: nil, requestedLineCount: candidates.count)
        }

        let executor: JSExecutor
        do {
            executor = try context.makeExecutor(scriptKey: "translate")
        } catch {
            AppLogger.shared.log("❌ [ExtTranslate] \(context.name): không nạp được translate.js — \(error.localizedDescription)")
            return failure(candidates, engineName: context.name, error: error, keeping: translations)
        }

        let batches = TranslationExtensionBatchPlanner.batches(
            pending, maxLines: context.maxLines, maxLength: context.maxLength, disablesSplitting: context.disablesSplitting
        )
        var failed = Set<Int>()
        var firstError: String?
        var requestCount = 0
        for batch in batches {
            if firstError != nil {
                failed.formUnion(batch.map(\.id))
                continue
            }
            do {
                var outputs: [Int: String] = [:]
                try await translateBatch(batch, executor: executor, context: context, job: job,
                                         outputs: &outputs, requestCount: &requestCount)
                for line in batch {
                    guard let text = outputs[line.id], !text.isEmpty else {
                        failed.insert(line.id)
                        continue
                    }
                    translations[line.id] = text
                    TranslationExtensionLineCache.shared.insert(text, for: line.text, scope: scope,
                                                                ticket: tickets[line.id] ?? 0)
                }
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                failed.formUnion(batch.map(\.id))
                firstError = TranslationExtensionResultParser.shortMessage(for: error)
                AppLogger.shared.log("❌ [ExtTranslate] \(context.name): lô \(batch.count) dòng lỗi — \(firstError ?? "")")
            }
        }
        AppLogger.shared.log("🌐 [ExtTranslate] \(context.name): \(candidates.count) dòng, \(pending.count) gọi mới, "
            + "\(requestCount) lần gọi, \(failed.count) lỗi")
        return TranslationExtensionLineResult(
            engineName: context.name, translations: translations, failedLineIds: failed,
            errorMessage: firstError ?? (failed.isEmpty ? nil : "Tiện ích trả thiếu bản dịch"),
            requestedLineCount: candidates.count
        )
    }

    // MARK: - Một đoạn (tên chương, Dịch thử)

    /// Dịch một đoạn chữ, ném lỗi khi tiện ích lỗi. Có dùng cache theo dòng (khoá = cả đoạn).
    static func translateText(_ text: String, job: Job) async throws -> String {
        try Task.checkCancellation()
        guard TranslationExtensionBatchPlanner.needsTranslation(text) else { return text }
        let context = try TranslationExtensionContext.load(packageId: job.packageId)
        let scope = TranslationExtensionLineCache.Scope(
            context: context, bookId: job.bookId, from: job.from, to: job.to, source: job.source
        )
        let cached = TranslationExtensionLineCache.shared.lookup(text, scope: scope)
        if let value = cached.value { return value }
        let executor = try context.makeExecutor(scriptKey: "translate")
        let output = try await call(executor, text: text, context: context, job: job)
        let translated = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else {
            throw TranslationExtensionResultParser.ShapeError(detail: "Tiện ích dịch trả bản dịch rỗng")
        }
        TranslationExtensionLineCache.shared.insert(translated, for: text, scope: scope, ticket: cached.ticket)
        return translated
    }

    // MARK: - Nội bộ

    /// Gọi một lô; lệch dòng ⇒ chia đôi đệ quy. Ghi bản dịch vào `outputs` theo id dòng.
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

    private static func failure(
        _ candidates: [Line],
        engineName: String,
        error: Error,
        keeping translations: [Int: String] = [:]
    ) -> TranslationExtensionLineResult {
        let failed = Set(candidates.map(\.id)).subtracting(translations.keys)
        return TranslationExtensionLineResult(
            engineName: engineName, translations: translations, failedLineIds: failed,
            errorMessage: TranslationExtensionResultParser.shortMessage(for: error), requestedLineCount: candidates.count
        )
    }
}
