import Foundation

/// Lối vào `++url` và việc chọn chương thử nội dung của bộ kiểm tra nguồn.
extension LegadoCorpusProbe {
    /// Lối vào `++url` (spec §5.10): URL là **trang mục lục**, không phải trang sách. Ghi `tocUrl` = chính URL đó vào trạng
    /// thái (bộ nhớ) của cặp (nguồn, URL) để bước mục lục phân tích thẳng trang đó thay vì chạy thông tin sách trên nó —
    /// như màn Gỡ lỗi từng bước (中文万维 `++…getvolume?bookId=…` từng bị chạy `ruleBookInfo` ⇒ `bookId` rỗng).
    static func seedTocURL(_ url: String, packageId: String, bookId: String) {
        LegadoBookStateStore.shared.commit(LegadoBookStateDelta(tocUrl: url), packageId: packageId, bookUrl: url,
                                           bookId: bookId, persist: false)
    }

    /// URL trang mục lục đã biết của sách: trang sách (mục lục nằm trên trang sách khi `tocUrl` rỗng) + `tocUrl` lưu trong
    /// trạng thái sau bước mục lục.
    static func knownTocPageURLs(packageId: String, bookURL: String, bookId: String) -> [String] {
        let stored = LegadoBookStateStore.shared.state(packageId: packageId, bookUrl: bookURL, bookId: bookId).tocUrl ?? ""
        return [bookURL, stored].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Chỉ số chương thử nội dung: dòng không phải tiêu đề nhóm, có URL, URL **khác** trang mục lục/trang sách và không
    /// trùng nguyên văn URL của dòng khác. Hàng tên quyển mà rule không đánh dấu `isVolume` có `chapterUrl` rỗng nên rơi về
    /// URL trang mục lục (`parseTocPage`) — "nội dung" của nó là trang mục lục (中文万维/中文书城: JSON mục lục ⇒ nội dung
    /// rỗng); các hàng đó cùng chung URL cuối của trang kể cả khi trang đã chuyển hướng. Không dòng nào đạt (truyện một
    /// trang) ⇒ dòng có URL đầu tiên. `nil` = không dòng nào có URL.
    static func testChapterIndex(_ chapters: [ChapterResult], tocPageURLs: [String]) -> Int? {
        let candidates = chapters.indices.filter { index in
            !chapters[index].isSection && !chapters[index].url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let pageKeys = Set(tocPageURLs.map(comparableURL).filter { !$0.isEmpty })
        var urlCounts: [String: Int] = [:]
        for index in candidates { urlCounts[chapters[index].url, default: 0] += 1 }
        let preferred = candidates.first { index in
            let url = chapters[index].url
            return (urlCounts[url] ?? 0) < 2 && !pageKeys.contains(comparableURL(url))
        }
        return preferred ?? candidates.first
    }

    /// URL để so với trang mục lục: bỏ khối option + fragment (`normalizedForComparison`), giải `%XX` (URL cuối của trang
    /// đã mã hoá, `tocUrl` do rule dựng có thể chưa).
    static func comparableURL(_ url: String) -> String {
        let normalized = LegadoURLResolver.normalizedForComparison(url.trimmingCharacters(in: .whitespacesAndNewlines))
        return normalized.removingPercentEncoding ?? normalized
    }
}
