import Foundation

/// Chủ sở hữu **duy nhất** của chỉ mục tìm toàn văn offline. Mọi thao tác ghi/xoá/tra đi qua đây.
///
/// Thiết kế cố ý **không throw ra ngoài** cho các đường ghi/xoá: chỉ mục là dữ liệu phái sinh,
/// dựng lại được, nên một lỗi chỉ mục **không bao giờ** được làm hỏng luồng lưu chương, nhập
/// truyện, khôi phục sao lưu hay xoá sách. Lỗi chỉ được ghi log.
///
/// Chỉ mục chỉ hoạt động khi `ChapterSearchPolicy.isEnabled == true`; khi tắt, mọi lời gọi ghi
/// thoát ngay ở dòng đầu nên chi phí là bằng không.
internal actor ChapterSearchIndex {
    /// Thông tin hiện trạng chỉ mục để hiện trong Cài đặt.
    internal struct Statistics: Sendable {
        internal let documentCount: Int
        internal let byteSize: Int64
    }

    internal static let shared = ChapterSearchIndex()

    private var database: ChapterSearchIndexDatabase?
    private var openFailed = false

    private init() {}

    /// Mở DB theo kiểu lazy. Mở thất bại một lần thì không thử lại trong phiên chạy này — tránh
    /// đập vào ổ đĩa mỗi lần cache một chương.
    private func ensureDatabase() -> ChapterSearchIndexDatabase? {
        if let database { return database }
        if openFailed { return nil }
        do {
            let url = try ChapterSearchIndexPath.makeDatabaseURL()
            let db = try ChapterSearchIndexDatabase(dbURL: url)
            database = db
            return db
        } catch {
            openFailed = true
            AppLogger.shared.log("[ChapterSearchIndex] Không mở được chỉ mục: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Ghi

    /// Ghi nội dung một chương vào chỉ mục. `content` phải là **đúng chuỗi** vừa được ghi vào
    /// `.bin` — nhờ vậy đoạn tính ra khi tìm mới trùng với đoạn Reader hiển thị.
    internal func indexChapter(
        bookId: String,
        chapterIndex: Int,
        chapterUrl: String,
        chapterTitle: String,
        content: String
    ) {
        guard ChapterSearchPolicy.isEnabled, !content.isEmpty else { return }
        guard let database = ensureDatabase() else { return }
        do {
            try database.upsert(
                bookId: bookId,
                chapterIndex: chapterIndex,
                chapterUrl: chapterUrl,
                chapterTitle: chapterTitle,
                content: content
            )
        } catch {
            AppLogger.shared.log("[ChapterSearchIndex] Ghi chỉ mục thất bại (chương \(chapterIndex)): \(error.localizedDescription)")
        }
    }

    // MARK: - Xoá

    /// Xoá chỉ mục của một truyện. **Không** gác theo `isEnabled`: người dùng tắt tính năng rồi
    /// xoá truyện thì chỉ mục cũ vẫn phải sạch, nếu không bật lại sẽ thấy kết quả của truyện đã xoá.
    internal func removeBook(bookId: String) {
        guard let database = ensureDatabase() else { return }
        do {
            try database.deleteBook(bookId: bookId)
        } catch {
            AppLogger.shared.log("[ChapterSearchIndex] Xoá chỉ mục truyện thất bại: \(error.localizedDescription)")
        }
    }

    internal func removeChapter(bookId: String, chapterIndex: Int, chapterUrl: String) {
        guard let database = ensureDatabase() else { return }
        do {
            try database.deleteChapter(bookId: bookId, chapterIndex: chapterIndex, chapterUrl: chapterUrl)
        } catch {
            AppLogger.shared.log("[ChapterSearchIndex] Xoá chỉ mục chương thất bại: \(error.localizedDescription)")
        }
    }

    /// Xoá sạch chỉ mục (dùng khi người dùng tắt tính năng hoặc bấm "Xoá chỉ mục").
    internal func clear() {
        guard let database = ensureDatabase() else { return }
        do {
            try database.clearAll()
        } catch {
            AppLogger.shared.log("[ChapterSearchIndex] Xoá chỉ mục thất bại: \(error.localizedDescription)")
        }
    }

    // MARK: - Tra

    /// Tìm toàn văn. Trả mảng rỗng khi tính năng tắt, truy vấn quá ngắn, hoặc chỉ mục chưa mở được.
    ///
    /// Kết quả được **đối chiếu lại với mục lục hiện tại** trong `ChapterStore`: mục lục có thể đã
    /// đánh số lại sau khi truyện ra chương mới, nên `chapter_index` lưu trong chỉ mục không còn
    /// chắc đúng. Chương còn URL nhưng đổi số ⇒ sửa số theo mục lục; chương biến mất khỏi mục lục
    /// ⇒ bỏ hit (mở Reader sẽ ra chương khác).
    internal func search(query rawQuery: String, bookId: String? = nil) async -> [ChapterSearchHit] {
        guard ChapterSearchPolicy.isEnabled,
              let query = ChapterSearchPolicy.normalizedQuery(rawQuery),
              let database = ensureDatabase() else { return [] }

        let rows: [ChapterSearchIndexDatabase.Row]
        do {
            rows = try database.search(
                matchExpression: ChapterSearchPolicy.matchExpression(for: query),
                bookId: bookId,
                limit: ChapterSearchPolicy.maxResults
            )
        } catch {
            AppLogger.shared.log("[ChapterSearchIndex] Truy vấn thất bại: \(error.localizedDescription)")
            return []
        }

        var hits: [ChapterSearchHit] = []
        var tocCache: [String: [String: Int]] = [:]
        for row in rows {
            guard var hit = ChapterSearchSnippetBuilder.makeHit(row: row, query: query) else { continue }
            let urlToIndex: [String: Int]
            if let cached = tocCache[row.bookId] {
                urlToIndex = cached
            } else {
                urlToIndex = await currentChapterIndexes(bookId: row.bookId)
                tocCache[row.bookId] = urlToIndex
            }
            if let liveIndex = urlToIndex[row.chapterUrl] {
                if liveIndex != hit.chapterIndex {
                    hit = ChapterSearchHit(
                        bookId: hit.bookId,
                        chapterIndex: liveIndex,
                        chapterUrl: hit.chapterUrl,
                        chapterTitle: hit.chapterTitle,
                        paragraphIndex: hit.paragraphIndex,
                        snippet: hit.snippet
                    )
                }
            } else if !urlToIndex.isEmpty {
                continue
            }
            hits.append(hit)
        }
        return hits
    }

    /// Bản đồ `url -> chapter_index` hiện tại của một truyện. Rỗng nghĩa là không đọc được mục lục
    /// — khi đó tin theo chỉ mục thay vì bỏ hết kết quả.
    private func currentChapterIndexes(bookId: String) async -> [String: Int] {
        do {
            let toc = try await ChapterStore.shared.fetchOrderedTOC(bookId: bookId)
            var map: [String: Int] = [:]
            map.reserveCapacity(toc.count)
            for chapter in toc {
                map[chapter.url] = chapter.index
            }
            return map
        } catch {
            return [:]
        }
    }

    // MARK: - Trạng thái

    internal func statistics() -> Statistics {
        let count: Int
        if let database = ensureDatabase() {
            count = (try? database.countDocuments(bookId: nil)) ?? 0
        } else {
            count = 0
        }
        return Statistics(documentCount: count, byteSize: ChapterSearchIndexPath.totalByteSize())
    }

    /// Đóng DB và checkpoint WAL. Gọi khi người dùng tắt tính năng để không giữ file mở vô ích.
    internal func close() {
        database?.checkpointAndClose()
        database = nil
        openFailed = false
    }
}
