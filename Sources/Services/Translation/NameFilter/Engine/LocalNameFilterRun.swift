import Foundation

/// Một lượt **Lọc name local** (Reader › "…" › "Lọc name local"): đọc các chương đã tải theo khối trên luồng nền, chạy
/// `LocalNameFilterEngine`, phát sự kiện qua `events` theo thứ tự `.progress` / `.update` … rồi `.finished` hoặc
/// `.failed` (sự kiện cuối, stream đóng ngay sau).
///
/// - Cập nhật dần như `run_live` của bản thử Python: sau mỗi khối, nếu từ lúc lần chụp trước **kết thúc** đã qua
///   ≥ max(1 s, 2 × thời gian lần chụp đó) thì chụp ⇒ `.update`. Khối cuối chỉ chụp một lần ⇒ `.finished`. Lần chụp nào
///   cũng phân tích lại toàn bộ phần đã đọc nên kết quả cuối y như chạy một lần.
/// - `stop()` ("Dừng"): thôi đọc chương mới, phân tích nốt phần đã đọc, phát `.finished`.
/// - `cancel()` (đóng sheet): huỷ task, đóng stream ngay, không phát `.finished`. Người nghe thôi lặp `events` cũng huỷ.
/// - Không chạy nền khi rời màn, không lưu tiến độ.
public final class LocalNameFilterRun: @unchecked Sendable {
    public let events: AsyncStream<LocalNameFilter.Event>
    private let continuation: AsyncStream<LocalNameFilter.Event>.Continuation
    private let lock = NSLock()
    private var isStopRequested = false
    private var task: Task<Void, Never>?

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
    private struct Metrics {
        var processed = 0
        var unreadable = 0
        var readMs = 0
        var passOneMs = 0
        var updates = 0
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
        let engine = LocalNameFilterEngine(configuration: configuration, dictionaries: dictionaries)
        var metrics = Metrics()
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
            let feedStart = Self.seconds()
            metrics.readMs += Self.milliseconds(feedStart - readStart)
            for text in loaded.texts {
                if let text { engine.feed(text) } else { metrics.unreadable += 1 }
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
        guard let final = reused ?? engine.snapshot(chaptersRead: metrics.processed) else { return }
        if Task.isCancelled { return }
        emit(.finished(final.snapshot))
        log(final, metrics: metrics, total: chapters.count, hanCount: engine.hanCount, stoppedEarly: stoppedEarly,
            hasPronouns: engine.hasPronouns)
    }

    private func emit(_ event: LocalNameFilter.Event) {
        guard !Task.isCancelled else { return }
        continuation.yield(event)
    }

    private func log(
        _ report: LocalNameFilterEngine.Report,
        metrics: Metrics,
        total: Int,
        hanCount: Int,
        stoppedEarly: Bool,
        hasPronouns: Bool
    ) {
        let snapshot = report.snapshot
        let dropped = snapshot.droppedByReason
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let stopNote = stoppedEarly ? " (bấm Dừng)" : ""
        let unreadableNote = metrics.unreadable > 0 ? " (\(metrics.unreadable) không đọc được)" : ""
        let titleNote = hasPronouns ? String(report.titleCount) : "tắt (chưa nạp Pronouns)"
        let parts: [String] = [
            "🔎 [LọcName] Xong\(stopNote): \(metrics.processed)/\(total) chương\(unreadableNote), \(hanCount) chữ Hán",
            "đọc \(metrics.readMs) ms",
            "lượt 1 \(metrics.passOneMs) ms",
            "lượt 2 \(report.passTwoMs) ms",
            "luật \(report.rulesMs) ms",
            "cập nhật \(metrics.updates) lần",
            "giữ \(snapshot.names.count)",
            "ẩn \(snapshot.hiddenKnownCount)",
            "bỏ [\(dropped)]",
            "danh xưng \(titleNote)"
        ]
        AppLogger.shared.log(parts.joined(separator: " · "))
    }

    private static func seconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private static func milliseconds(_ seconds: Double) -> Int {
        Int((seconds * 1000).rounded())
    }
}
