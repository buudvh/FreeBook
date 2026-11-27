import Foundation

/// Một lượt **Lọc name local** (Reader › "…" › "Lọc name local"): chuẩn bị model LAC, đọc các chương đã tải theo khối trên
/// luồng nền, gắn nhãn LAC song song theo chương, chạy `LocalNameFilterEngine`, phát sự kiện qua `events` theo thứ tự
/// `.preparingModel` … / `.progress` / `.update` … rồi `.finished` hoặc `.failed` (sự kiện cuối, stream đóng ngay sau).
///
/// - Model (`LACModel.prepare`, trước khi đọc chương — sau khi chụp từ điển để thiếu VP thì báo ngay, không tải 19 MB):
///   tải / nạp ⇒ `.preparingModel(fraction:)` (thưa ≥ 1 %); tải lỗi / file hỏng ⇒ `.failed`; tự kiểm lệch ⇒ log ❌ rồi
///   chạy **chỉ bộ luật** như trước bản LAC.
/// - Cập nhật dần như `run_live` của bản thử Python: sau mỗi khối, nếu từ lúc lần chụp trước **kết thúc** đã qua
///   ≥ max(1 s, 2 × thời gian lần chụp đó) thì chụp ⇒ `.update`. Khối cuối chỉ chụp một lần ⇒ `.finished`. Lần chụp nào
///   cũng phân tích lại toàn bộ phần đã đọc nên kết quả cuối y như chạy một lần.
/// - `stop()` ("Dừng"): thôi đọc chương mới (khối đang gắn nhãn chạy nốt), phân tích nốt phần đã đọc, phát `.finished`.
/// - `cancel()` (đóng sheet): huỷ task, đóng stream ngay, không phát `.finished`. Người nghe thôi lặp `events` cũng huỷ.
/// - Không chạy nền khi rời màn, không lưu tiến độ.
public final class LocalNameFilterRun: @unchecked Sendable {
    public let events: AsyncStream<LocalNameFilter.Event>
    private let continuation: AsyncStream<LocalNameFilter.Event>.Continuation
    private let lock = NSLock()
    private var isStopRequested = false
    private var task: Task<Void, Never>?
    /// Phần trăm tải model đã phát gần nhất (−1 = chưa) / đã phát "đang nạp" chưa — chỉ đọc ghi trong `lock`.
    private var lastModelFraction = -1.0
    private var didEmitModelLoading = false

    /// Số chương mỗi lần đọc (`BookBinManager` một `FileHandle` mỗi khối) — cũng là nhịp `.progress`.
    private static let chunkSize = 24

    private init() {
        let (stream, continuation) = AsyncStream.makeStream(of: LocalNameFilter.Event.self)
        events = stream
        self.continuation = continuation
    }

    /// Bắt đầu ngay trên luồng nền. `chapters` theo thứ tự đọc (đã chọn sẵn phạm vi).
    ///
    /// `internal` (hợp đồng ghi `public`): `StoredChapterSnapshot` là kiểu `internal` nên hàm `public` không biên dịch được;
    /// app một module nên nơi gọi không đổi gì.
    static func start(
        bookId: String,
        chapters: [StoredChapterSnapshot],
        convertsTraditional: Bool,
        configuration: LocalNameFilter.Configuration
    ) -> LocalNameFilterRun {
        let run = LocalNameFilterRun()
        run.continuation.onTermination = { @Sendable [weak run] _ in
            run?.cancelTask()
        }
        let task = Task.detached(priority: .userInitiated) {
            await run.execute(
                bookId: bookId, chapters: chapters, convertsTraditional: convertsTraditional, configuration: configuration
            )
        }
        run.lock.lock()
        run.task = task
        run.lock.unlock()
        return run
    }

    /// "Dừng": thôi đọc, phân tích nốt phần đã đọc, phát `.finished` rồi đóng stream.
    public func stop() {
        lock.lock()
        isStopRequested = true
        lock.unlock()
    }

    /// Huỷ (đóng sheet): dừng ngay, không phát `.finished`, đóng stream.
    public func cancel() {
        cancelTask()
        continuation.finish()
    }

    private func cancelTask() {
        lock.lock()
        let current = task
        lock.unlock()
        current?.cancel()
    }

    private var stopRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopRequested
    }

    // MARK: - Chạy

    /// Số đo của một lượt cho dòng log cuối.
    struct Metrics {
        var processed = 0
        var unreadable = 0
        var readMs = 0
        var passOneMs = 0
        var updates = 0
        var modelMs = 0
        var lacMs = 0
    }

    private enum ModelOutcome {
        case tagger(any LACTagging)
        /// Model tự kiểm lệch ⇒ chỉ bộ luật.
        case rulesOnly
        /// Đã phát `.failed` hoặc bị huỷ.
        case stop
    }

    private func execute(
        bookId: String,
        chapters: [StoredChapterSnapshot],
        convertsTraditional: Bool,
        configuration: LocalNameFilter.Configuration
    ) async {
        defer { continuation.finish() }
        guard !chapters.isEmpty else {
            emit(.failed("Không có chương đã tải nào trong phạm vi đã chọn"))
            return
        }
        guard let dictionaries = LocalNameFilterDictionaries.capture(bookId: bookId) else {
            AppLogger.shared.log("🔎 [LọcName] Chưa nạp từ điển VietPhrase — không lọc")
            emit(.failed("Chưa nạp từ điển VietPhrase — mở Cài đặt dịch thuật để tải / làm mới dữ liệu"))
            return
        }
        if dictionaries.pronounEntries == nil {
            AppLogger.shared.log("🔎 [LọcName] Chưa nạp từ điển Đại từ (Pronouns) — bỏ bước danh xưng")
        }
        var metrics = Metrics()
        let modelStart = Self.seconds()
        let tagger: (any LACTagging)?
        switch await prepareModel() {
        case .tagger(let ready): tagger = ready
        case .rulesOnly: tagger = nil
        case .stop: return
        }
        metrics.modelMs = Self.milliseconds(Self.seconds() - modelStart)
        if Task.isCancelled { return }

        let engine = LocalNameFilterEngine(configuration: configuration, dictionaries: dictionaries, usesLAC: tagger != nil)
        let suffixLastScalars = engine.lacSuffixLastScalars
        var stoppedEarly = false
        var lastReport: (report: LocalNameFilterEngine.Report, chapters: Int)?
        var lastEnd = Self.seconds()
        var lastCost = 0.0
        var loggedReadFailure = false

        while metrics.processed < chapters.count {
            if Task.isCancelled { return }
            if stopRequested {
                stoppedEarly = true
                break
            }
            let chunk = Array(chapters[metrics.processed..<min(metrics.processed + Self.chunkSize, chapters.count)])
            let readStart = Self.seconds()
            let loaded = await LocalNameFilterChapterReader.read(
                bookId: bookId, chapters: chunk, convertsTraditional: convertsTraditional
            )
            if Task.isCancelled { return }
            if let failure = loaded.failure, !loggedReadFailure {
                loggedReadFailure = true
                AppLogger.shared.log("❌ 🔎 [LọcName] Không đọc được ch.\((chunk.first?.index ?? 0) + 1)–ch.\((chunk.last?.index ?? 0) + 1): \(failure)")
            }
            metrics.readMs += Self.milliseconds(Self.seconds() - readStart)
            var tagged: [LocalNameFilterLACChapterTagger.Chapter?] = []
            if let tagger {
                let lacStart = Self.seconds()
                guard let result = await LocalNameFilterLACChapterTagger.tag(
                    loaded.texts, tagger: tagger, suffixLastScalars: suffixLastScalars
                ) else { return }
                tagged = result
                metrics.lacMs += Self.milliseconds(Self.seconds() - lacStart)
            }
            let feedStart = Self.seconds()
            for (position, text) in loaded.texts.enumerated() {
                guard let text else {
                    metrics.unreadable += 1
                    continue
                }
                engine.feed(text)
                if position < tagged.count, let chapter = tagged[position] { engine.feedLAC(chapter) }
            }
            metrics.passOneMs += Self.milliseconds(Self.seconds() - feedStart)
            metrics.processed += chunk.count
            emit(.progress(chaptersRead: metrics.processed, total: chapters.count))

            guard metrics.processed < chapters.count, !stopRequested else { continue }
            let now = Self.seconds()
            guard now - lastEnd >= max(1.0, 2 * lastCost) else { continue }
            guard let report = engine.snapshot(chaptersRead: metrics.processed) else { return }
            lastEnd = Self.seconds()
            lastCost = lastEnd - now
            lastReport = (report, metrics.processed)
            metrics.updates += 1
            emit(.update(report.snapshot))
        }

        if Task.isCancelled { return }
        if metrics.processed > 0, metrics.unreadable == metrics.processed {
            AppLogger.shared.log("❌ 🔎 [LọcName] Không đọc được chương nào (\(metrics.processed) chương)")
            emit(.failed("Không đọc được nội dung chương nào — thử tải lại các chương này"))
            return
        }
        // Không đọc thêm chương nào từ lần chụp trước ⇒ lần chụp đó chính là kết quả cuối.
        let reused = lastReport?.chapters == metrics.processed ? lastReport?.report : nil
        guard let finalReport = reused ?? engine.snapshot(chaptersRead: metrics.processed) else { return }
        if Task.isCancelled { return }
        emit(.finished(finalReport.snapshot))
        LocalNameFilterRunLog.write(
            finalReport, metrics: metrics, total: chapters.count, hanCount: engine.hanCount,
            stoppedEarly: stoppedEarly, hasPronouns: engine.hasPronouns, usesLAC: engine.usesLAC,
            taggedLines: engine.lacTaggedLines
        )
    }

    /// `LACModel.prepare` + phân loại lỗi theo hợp đồng `LACModelError`.
    private func prepareModel() async -> ModelOutcome {
        do {
            let tagger = try await LACModel.prepare { [weak self] fraction in
                self?.emitModelProgress(fraction)
            }
            return .tagger(tagger)
        } catch is CancellationError {
            return .stop
        } catch let error as LACModelError {
            if Task.isCancelled { return .stop }
            switch error {
            case .selfCheckFailed(let why):
                AppLogger.shared.log("❌ 🔎 [LọcName] Model LAC tự kiểm lệch — lọc bằng bộ luật cũ: \(why)")
                return .rulesOnly
            case .downloadFailed, .invalidFiles:
                AppLogger.shared.log("❌ 🔎 [LọcName] \(error.localizedDescription)")
                emit(.failed(error.localizedDescription))
                return .stop
            }
        } catch {
            if Task.isCancelled { return .stop }
            AppLogger.shared.log("❌ 🔎 [LọcName] Không chuẩn bị được model LAC: \(error.localizedDescription)")
            emit(.failed(error.localizedDescription))
            return .stop
        }
    }

    /// Phát `.preparingModel` thưa: phần trăm tải tăng ≥ 1 % (hoặc chạm 100 %), "đang nạp" (`nil`) một lần. Gọi được từ
    /// luồng bất kỳ (hàng đợi của phiên tải) ⇒ yield thẳng vào continuation, không qua `emit`.
    private func emitModelProgress(_ fraction: Double?) {
        lock.lock()
        let shouldEmit: Bool
        if let fraction {
            shouldEmit = fraction - lastModelFraction >= 0.01 || (fraction >= 1 && lastModelFraction < 1)
            if shouldEmit { lastModelFraction = fraction }
        } else {
            shouldEmit = !didEmitModelLoading
            didEmitModelLoading = true
        }
        lock.unlock()
        if shouldEmit { continuation.yield(.preparingModel(fraction: fraction)) }
    }

    private func emit(_ event: LocalNameFilter.Event) {
        guard !Task.isCancelled else { return }
        continuation.yield(event)
    }

    static func seconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    static func milliseconds(_ seconds: Double) -> Int {
        Int((seconds * 1000).rounded())
    }
}
