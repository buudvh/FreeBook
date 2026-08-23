import Combine
import Foundation

/// Điều phối viên **duy nhất** của hộp thư chương mới: giữ trạng thái cho UI, gọi
/// [`NewChapterProbe`](NewChapterProbe.swift) tuần tự và lưu qua
/// [`NewChapterStore`](NewChapterStore.swift).
///
/// Nằm ở tầng Services nên **không** `import SwiftUI` và **không** gọi `ToastManager` — summary được
/// **trả về** cho View để View tự hiện toast (cùng lý do các service khác dùng event center).
///
/// Một lượt kiểm tra chạy **tuần tự**, nghỉ `interBookDelayNanoseconds` giữa hai truyện: mục đích là
/// không đấu băng thông với việc đọc/tải của người dùng, nên tuyệt đối không đổi sang `TaskGroup`.
@MainActor
final class NewChapterInboxManager: ObservableObject {
    static let shared = NewChapterInboxManager()

    /// Kết quả gộp của một lượt để View hiện đúng một toast.
    struct BatchSummary: Equatable, Sendable {
        var bookCount: Int = 0
        var chapterCount: Int = 0
        /// Có ít nhất một truyện chỉ đếm được ước lượng ⇒ câu toast phải dùng "≥".
        var hasInexact: Bool = false
        var failureCount: Int = 0
        var checkedCount: Int = 0

        var isEmpty: Bool { bookCount == 0 && failureCount == 0 }
    }

    @Published private(set) var records: [String: NewChapterRecord] = [:]
    @Published private(set) var isChecking = false
    @Published private(set) var checkProgress: String = ""

    private var didLoad = false

    private init() {}

    /// Tổng số **truyện** có chương mới — dùng cho badge tab.
    var totalNewBooks: Int {
        records.values.reduce(0) { $0 + ($1.hasNew ? 1 : 0) }
    }

    func record(for bookId: String) -> NewChapterRecord? {
        records[bookId]
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        records = await NewChapterStore.shared.all()
    }

    func prune(keeping bookIds: Set<String>) async {
        guard await NewChapterStore.shared.prune(keeping: bookIds) else { return }
        records = await NewChapterStore.shared.all()
    }

    /// Người dùng đã mở truyện ⇒ tắt badge. Không có gì mới thì không ghi đĩa.
    func markSeen(bookId: String) {
        guard var record = records[bookId], record.hasNew else { return }
        record.markSeen()
        records[bookId] = record
        Task { await NewChapterStore.shared.save(record) }
    }

    /// Lượt tự động: qua cửa `NewChapterCheckPolicy` mới chạy, và chỉ lấy
    /// `maxBooksPerBatch` truyện đọc gần nhất.
    func autoCheck(targets: [NewChapterProbe.Target]) async -> BatchSummary? {
        guard NewChapterCheckPolicy.shouldRunBatch() else { return nil }
        await loadIfNeeded()
        let due = targets.filter { NewChapterCheckPolicy.shouldCheck(record: records[$0.bookId]) }
        let batch = Array(due.prefix(NewChapterCheckPolicy.maxBooksPerBatch))
        guard !batch.isEmpty else {
            NewChapterCheckPolicy.markBatchRun()
            return nil
        }
        let summary = await run(batch)
        NewChapterCheckPolicy.markBatchRun()
        return summary
    }

    /// Refresh tay toàn bộ: **bỏ qua** cooldown và cả cờ bật/tắt, nhưng vẫn giữ trần số truyện.
    func checkAll(targets: [NewChapterProbe.Target]) async -> BatchSummary? {
        await loadIfNeeded()
        let batch = Array(targets.prefix(NewChapterCheckPolicy.maxBooksPerBatch))
        guard !batch.isEmpty else { return nil }
        let summary = await run(batch)
        NewChapterCheckPolicy.markBatchRun()
        return summary
    }

    /// Refresh tay một truyện.
    func check(target: NewChapterProbe.Target) async -> BatchSummary? {
        await loadIfNeeded()
        return await run([target])
    }

    // MARK: - Vòng chạy

    private func run(_ targets: [NewChapterProbe.Target]) async -> BatchSummary? {
        guard !isChecking else { return nil }
        isChecking = true
        defer {
            isChecking = false
            checkProgress = ""
        }

        var summary = BatchSummary()
        var pending: [NewChapterRecord] = []

        for (index, target) in targets.enumerated() {
            if Task.isCancelled { break }
            checkProgress = "\(index + 1)/\(targets.count)"
            let outcome = await NewChapterProbe.probe(target: target, previous: records[target.bookId])
            records[target.bookId] = outcome.record
            pending.append(outcome.record)
            summary.checkedCount += 1

            if outcome.failure != nil {
                summary.failureCount += 1
            } else if outcome.newlyFound > 0 {
                summary.bookCount += 1
                summary.chapterCount += outcome.newlyFound
                if !outcome.record.isCountExact {
                    summary.hasInexact = true
                }
            }

            if index < targets.count - 1 {
                try? await Task.sleep(nanoseconds: NewChapterCheckPolicy.interBookDelayNanoseconds)
            }
        }

        if !pending.isEmpty {
            await NewChapterStore.shared.save(pending)
        }
        return summary
    }
}
