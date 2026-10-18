import Foundation

/// Khoá đối chiếu hàng mục lục đang lưu với mục lục vừa lấy về (`ChapterStoreDatabase.replaceFullTOC` / `upsertPage`).
internal struct CompositeKey: Hashable, Sendable {
    internal let url: String
    internal let index: Int

    /// Chương có url khớp **theo url**: nguồn thêm/xoá một chương phía trước làm chỉ số các chương sau xê dịch,
    /// nhưng hàng cũ vẫn giữ `id`, `is_cached`, `offset`, `length` và chỉ đổi `chapter_index`.
    /// Chỉ chương không có url mới phải khớp theo chỉ số.
    internal static func reconcile(url: String, index: Int) -> CompositeKey {
        url.isEmpty ? CompositeKey(url: "", index: index) : CompositeKey(url: url, index: -1)
    }

    /// Hàng đợi ứng viên theo khoá, giữ thứ tự `chapter_index`. Cùng một url có nhiều hàng (rác do bản cũ khớp
    /// theo url + chỉ số để lại) thì hàng đã cache đứng trước, để không xoá nhầm bản có nội dung đã tải.
    internal static func candidateMap(for rows: [StoredChapterSnapshot]) -> [CompositeKey: [StoredChapterSnapshot]] {
        var map: [CompositeKey: [StoredChapterSnapshot]] = [:]
        for row in rows {
            map[reconcile(url: row.url, index: row.index), default: []].append(row)
        }
        for (key, queue) in map where queue.count > 1 {
            map[key] = queue.filter { $0.isCached } + queue.filter { !$0.isCached }
        }
        return map
    }
}
