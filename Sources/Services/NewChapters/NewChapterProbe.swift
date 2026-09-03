import Foundation

/// Một lượt dò mục lục cho **một** truyện: lấy TOC, so với mốc đã thấy, trả về record mới.
///
/// Chỉ gọi `BookDetailLoader` — tức chỉ tải **mục lục**, không bao giờ tải nội dung chương.
/// Không ghi đĩa, không phát toast, không đụng SwiftData: mọi quyết định lưu trữ thuộc
/// [`NewChapterInboxManager`](NewChapterInboxManager.swift).
///
/// ### Vì sao phải có `isCountExact`
/// Nguồn phân trang mục lục có thể tới 50 trang; tải hết cho mỗi truyện mỗi lượt là không chấp nhận
/// được. Quá `NewChapterCheckPolicy.maxTOCPagesPerCheck` trang thì probe chỉ lấy **trang cuối**, nên nó
/// biết "có chương lạ" nhưng **không** biết tổng số chương ⇒ đánh `isCountExact = false` và UI hiện dấu
/// chấm thay vì một con số sai.
enum NewChapterProbe {
    struct Target: Sendable {
        let bookId: String
        let title: String
        let detailUrl: String
        let host: String?
        let snapshot: ExtensionExecutionSnapshot
    }

    struct Outcome: Sendable {
        let bookId: String
        let title: String
        let record: NewChapterRecord
        /// Số chương mới **vừa phát hiện trong lượt này** (đã trừ phần đã biết từ trước).
        let newlyFound: Int
        let failure: String?
    }

    static func probe(target: Target, previous: NewChapterRecord?) async -> Outcome {
        var record = previous ?? NewChapterRecord(bookId: target.bookId)
        record.bookId = target.bookId
        let previousNewCount = record.newChapterCount
        record.lastCheckedAt = Date()

        let fetched: (chapters: [(name: String, url: String)], isPartial: Bool)
        do {
            fetched = try await fetchTOC(target: target)
        } catch {
            record.lastFailure = error.localizedDescription
            return Outcome(
                bookId: target.bookId,
                title: target.title,
                record: record,
                newlyFound: 0,
                failure: error.localizedDescription
            )
        }

        let chapters = dedupePreservingOrder(fetched.chapters)
        guard let last = chapters.last else {
            let message = "Mục lục trống"
            record.lastFailure = message
            return Outcome(
                bookId: target.bookId,
                title: target.title,
                record: record,
                newlyFound: 0,
                failure: message
            )
        }

        record.lastFailure = nil
        record.probedChapterCount = chapters.count
        record.probedLastChapterUrl = last.url
        record.probedIsPartial = fetched.isPartial
        record.latestChapterTitle = last.name

        let baseline = await resolveBaseline(record: record, bookId: target.bookId)
        record.seenChapterCount = baseline.count
        record.seenLastChapterUrl = baseline.lastUrl

        applyDiff(to: &record, chapters: chapters, isPartial: fetched.isPartial, baseline: baseline)

        if record.newChapterCount > 0 {
            if record.firstFoundAt == nil {
                record.firstFoundAt = Date()
            }
            // Dòng trong Trung tâm thông báo sống độc lập với badge — xem `NewChapterRecord`.
            record.announceCurrentFinding()
        } else {
            record.firstFoundAt = nil
        }

        return Outcome(
            bookId: target.bookId,
            title: target.title,
            record: record,
            newlyFound: max(0, record.newChapterCount - previousNewCount),
            failure: nil
        )
    }

    // MARK: - Tải mục lục

    /// Trả về mục lục **theo đúng thứ tự nguồn** và cờ "chỉ lấy được một phần".
    private static func fetchTOC(
        target: Target
    ) async throws -> (chapters: [(name: String, url: String)], isPartial: Bool) {
        let first = try await BookDetailLoader.shared.fetchFirstPageTOC(
            snapshot: target.snapshot,
            url: target.detailUrl,
            host: target.host
        )
        let flatFirst = first.chapters.map { (name: $0.name, url: $0.url) }

        guard first.pages.count > 1 else {
            return (flatFirst, false)
        }

        if first.pages.count <= NewChapterCheckPolicy.maxTOCPagesPerCheck {
            let rest = try await BookDetailLoader.shared.fetchRemainingPages(
                snapshot: target.snapshot,
                pages: first.pages,
                host: target.host
            )
            return (flatFirst + rest.map { (name: $0.name, url: $0.url) }, false)
        }

        // Quá nhiều trang: chỉ trang cuối. Không đoán tổng số chương từ đây.
        guard let lastPage = first.pages.last else {
            return (flatFirst, false)
        }
        let tail = try await BookDetailLoader.shared.fetchPageTOC(
            snapshot: target.snapshot,
            url: lastPage,
            host: target.host
        )
        return (tail.map { (name: $0.name, url: $0.url) }, true)
    }

    private static func dedupePreservingOrder(
        _ chapters: [(name: String, url: String)]
    ) -> [(name: String, url: String)] {
        var seen = Set<String>()
        var result: [(name: String, url: String)] = []
        result.reserveCapacity(chapters.count)
        for chapter in chapters where !chapter.url.isEmpty {
            if seen.insert(chapter.url).inserted {
                result.append(chapter)
            }
        }
        return result
    }

    // MARK: - Mốc đã thấy

    /// Lần kiểm tra đầu tiên chưa có mốc nào ⇒ lấy từ mục lục **đã lưu trong máy** để không báo
    /// "toàn bộ truyện là chương mới".
    private static func resolveBaseline(
        record: NewChapterRecord,
        bookId: String
    ) async -> (count: Int, lastUrl: String, exists: Bool) {
        if !record.seenLastChapterUrl.isEmpty || record.seenChapterCount > 0 {
            return (record.seenChapterCount, record.seenLastChapterUrl, true)
        }
        do {
            let stored = try await ChapterStore.shared.fetchOrderedTOC(bookId: bookId)
            guard let last = stored.last else { return (0, "", false) }
            return (stored.count, last.url, true)
        } catch {
            AppLogger.shared.log("[NewChapterProbe] Không đọc được mục lục local: \(error.localizedDescription)")
            return (0, "", false)
        }
    }

    /// Bốn nhánh, xét theo thứ tự tin cậy giảm dần.
    private static func applyDiff(
        to record: inout NewChapterRecord,
        chapters: [(name: String, url: String)],
        isPartial: Bool,
        baseline: (count: Int, lastUrl: String, exists: Bool)
    ) {
        guard baseline.exists else {
            // Chưa từng có mốc: chỉ ghi mốc, không báo chương mới.
            record.newChapterCount = 0
            record.isCountExact = true
            if !isPartial {
                record.seenChapterCount = chapters.count
            }
            record.seenLastChapterUrl = chapters.last?.url ?? ""
            return
        }

        if let lastUrl = chapters.last?.url, lastUrl == baseline.lastUrl {
            record.newChapterCount = 0
            record.isCountExact = true
            return
        }

        if !baseline.lastUrl.isEmpty,
           let anchorIndex = chapters.lastIndex(where: { $0.url == baseline.lastUrl }) {
            record.newChapterCount = max(0, chapters.count - 1 - anchorIndex)
            record.isCountExact = true
            return
        }

        // Không tìm thấy mốc trong phần mục lục lấy được ⇒ mọi con số chỉ là ước lượng.
        // Chỉ lấy được trang cuối thì thậm chí không có tổng số chương để trừ, nên báo 1 (dấu chấm).
        if isPartial {
            record.newChapterCount = 1
            record.isCountExact = false
            return
        }
        // Số chương không tăng mà url chương cuối đổi ⇒ nguồn đổi đường dẫn, không phải chương mới.
        record.newChapterCount = max(0, chapters.count - baseline.count)
        record.isCountExact = record.newChapterCount == 0
    }
}
