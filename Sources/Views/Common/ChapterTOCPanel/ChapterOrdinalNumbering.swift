import Foundation

/// Số thứ tự hiển thị của chương trong một danh sách mục lục: tab Mục lục của Chi tiết, mục lục Reader, mục lục comic.
///
/// - Số = vị trí (đánh từ 1) của chương trong **mục lục đầy đủ**, theo thứ tự gốc. Tìm/lọc hay đảo thứ tự (↓↑) thì
///   mỗi chương vẫn giữ số của nó — dựng từ danh sách đủ, đừng dựng từ danh sách đã lọc/đảo.
/// - Dòng tiêu đề nhóm (`isSection`) không có số và không chiếm số ⇒ số lớn nhất = N của "Mục lục (N chương)".
/// - Dựng **một lần cho mỗi danh sách** (không dựng trong từng hàng). Mục lục liền mạch không có dòng nhóm (mọi truyện
///   chữ) ⇒ số = chỉ số + 1, không dựng bảng; có dòng nhóm (comic/video nhiều server) mới dựng bảng chỉ số → số.
struct ChapterOrdinalNumbering {
    /// Khoá `@AppStorage` của công tắc "Hiện số thứ tự chương" (Cài đặt › Chung › Giao diện). Không có dấu chấm (1.3.637).
    static let showsOrdinalKey = "chapterListShowsOrdinal"
    static let showsOrdinalDefault = true
    static let empty = ChapterOrdinalNumbering(chapterCount: 0)

    /// Số chương đọc được (không tính dòng tiêu đề nhóm) = số lớn nhất.
    let chapterCount: Int
    /// Số chữ số của số lớn nhất = bề rộng cột số (2000 → 4, 10000 → 5).
    let digits: Int
    /// `nil` = mục lục liền mạch `0..<chapterCount` ⇒ số = chỉ số + 1.
    private let ordinalsByIndex: [Int: Int]?

    /// Mục lục liền mạch `0..<chapterCount`, không có dòng nhóm.
    init(chapterCount: Int) {
        self.init(count: chapterCount, ordinalsByIndex: nil)
    }

    /// `rows` = **toàn bộ** mục lục theo thứ tự gốc (chỉ số tăng dần).
    init<Rows: Collection>(_ rows: Rows, index: (Rows.Element) -> Int, isSection: (Rows.Element) -> Bool) {
        var position = 0
        for row in rows {
            guard !isSection(row), index(row) == position else { break }
            position += 1
        }
        guard position < rows.count else {
            self.init(count: position, ordinalsByIndex: nil)
            return
        }
        var table: [Int: Int] = [:]
        table.reserveCapacity(rows.count)
        var count = 0
        for row in rows where !isSection(row) {
            count += 1
            table[index(row)] = count
        }
        self.init(count: count, ordinalsByIndex: table)
    }

    private init(count: Int, ordinalsByIndex: [Int: Int]?) {
        chapterCount = max(0, count)
        digits = String(chapterCount).count
        self.ordinalsByIndex = ordinalsByIndex
    }

    /// Số của chương có chỉ số `index`; `nil` = dòng tiêu đề nhóm hoặc chỉ số không có trong mục lục.
    func ordinal(forIndex index: Int) -> Int? {
        guard let ordinalsByIndex else {
            return index >= 0 && index < chapterCount ? index + 1 : nil
        }
        return ordinalsByIndex[index]
    }
}
