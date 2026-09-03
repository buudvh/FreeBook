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

    /// Các dòng "có chương mới" của Trung tâm thông báo. Khác `totalNewBooks`: dòng **ở lại** sau khi
    /// đánh dấu đã đọc, chỉ mất khi người dùng tự xoá.
    ///
    /// Sắp xếp ngay ở đây (mới nhất trước, `bookId` phá hoà) vì `records` là dictionary — thứ tự lặp
    /// không xác định, để View tự sort theo ngày thì hai dòng cùng mốc sẽ đổi chỗ giữa các lần vẽ.
    var announcements: [NewChapterRecord] {
        records.values
            .filter { $0.hasAnnouncement }
            .sorted { lhs, rhs in
                let left = lhs.announcedAt ?? .distantPast
                let right = rhs.announcedAt ?? .distantPast
                if left != right { return left > right }
                return lhs.bookId < rhs.bookId
            }
    }

    /// Có dòng chương mới nào **đã đọc** để dọn không — dùng cho mục "Xoá thông báo đã đọc".
    var hasReadAnnouncement: Bool {
        records.values.contains { $0.hasAnnouncement && $0.isAnnouncementRead }
    }

    func record(for bookId: String) -> NewChapterRecord? {
        records[bookId]
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        records = await NewChapterStore.shared.all()
        backfillAnnouncements()
    }

    /// `new_chapters.json` của bản app trước 1.3.329 chỉ có `newChapterCount`. Dựng thông báo tương
    /// ứng để người vừa cập nhật không thấy Trung tâm thông báo trống trong khi badge vẫn sáng.
    private func backfillAnnouncements() {
        var updated: [NewChapterRecord] = []
        for var record in Array(records.values) where record.hasNew && !record.hasAnnouncement {
            record.announceCurrentFinding(at: record.firstFoundAt ?? record.lastCheckedAt ?? Date())
            records[record.bookId] = record
            updated.append(record)
        }
        guard !updated.isEmpty else { return }
        Task { await NewChapterStore.shared.save(updated) }
    }

    func prune(keeping bookIds: Set<String>) async {
        guard await NewChapterStore.shared.prune(keeping: bookIds) else { return }
        records = await NewChapterStore.shared.all()
    }

    /// Người dùng đã mở truyện (hoặc bấm dòng thông báo) ⇒ tắt badge **và** đánh dấu dòng đã đọc.
    /// Dòng thông báo vẫn ở lại Trung tâm thông báo. Không có gì đổi thì không ghi đĩa.
    func markSeen(bookId: String) {
        guard var record = records[bookId] else { return }
        let clearsBadge = record.hasNew
        let marksRead = record.hasAnnouncement && !record.isAnnouncementRead
        guard clearsBadge || marksRead else { return }
        if clearsBadge {
            record.markSeen()
        }
        record.markAnnouncementRead()
        records[bookId] = record
        Task { await NewChapterStore.shared.save(record) }
    }

    /// Xoá **một** dòng khỏi Trung tâm thông báo. Chỉ bỏ thông báo, giữ mốc đã thấy để lượt kiểm tra
    /// sau không báo lại từ đầu.
    func clearAnnouncement(bookId: String) {
        guard var record = records[bookId], record.hasAnnouncement else { return }
        record.clearAnnouncement()
        records[bookId] = record
        Task { await NewChapterStore.shared.save(record) }
    }

    /// "Xoá thông báo đã đọc" — chỉ bỏ dòng **đã** đọc. Trả về số dòng đã xoá.
    @discardableResult
    func clearReadAnnouncements() -> Int {
        let targets = records.values.filter { $0.hasAnnouncement && $0.isAnnouncementRead }
        guard !targets.isEmpty else { return 0 }
        var updated: [NewChapterRecord] = []
        for var record in targets {
            record.clearAnnouncement()
            records[record.bookId] = record
            updated.append(record)
        }
        Task { await NewChapterStore.shared.save(updated) }
        return targets.count
    }

    /// Đánh dấu đã đọc mọi dòng thông báo trong một lần ghi đĩa.
    func markAllAnnouncementsRead() {
        var updated: [NewChapterRecord] = []
        // Chụp mảng trước khi vòng lặp ghi vào `records` — không lặp trực tiếp trên view của dictionary
        // đang bị sửa.
        for var record in Array(records.values) {
            let clearsBadge = record.hasNew
            let marksRead = record.hasAnnouncement && !record.isAnnouncementRead
            guard clearsBadge || marksRead else { continue }
            if clearsBadge {
                record.markSeen()
            }
            record.markAnnouncementRead()
            records[record.bookId] = record
            updated.append(record)
        }
        guard !updated.isEmpty else { return }
        Task { await NewChapterStore.shared.save(updated) }
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
