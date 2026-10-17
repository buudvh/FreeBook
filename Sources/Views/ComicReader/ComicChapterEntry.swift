import Foundation

/// Một dòng mục lục của màn đọc comic, gộp từ `StoredChapterSnapshot` (đã lưu) hoặc `ChapterResult` (online).
struct ComicChapterEntry: Equatable {
    let index: Int
    let title: String
    let titleTrans: String?
    let url: String
    let host: String?
    /// Dòng tiêu đề nhóm tập (`type: "section"`, ext nhiều server): không có ảnh, không mở được — mục lục hiện thành
    /// tiêu đề, điều hướng chương bỏ qua.
    var isSection: Bool = false

    /// Tên hiển thị: dùng `titleTrans` khi bật dịch và đã có bản dịch, còn lại là tên gốc.
    func displayTitle(translated: Bool) -> String {
        if translated, let trans = titleTrans?.trimmingCharacters(in: .whitespacesAndNewlines), !trans.isEmpty {
            return trans
        }
        return title
    }

    // MARK: - Điều hướng bỏ qua dòng tiêu đề nhóm

    /// Chương mở được ứng với `index`: chính nó nếu là chương thường (hoặc không có trong mục lục); dòng tiêu đề
    /// nhóm ⇒ chương thường kế tiếp, không còn thì chương thường ngay trước.
    static func openableIndex(_ index: Int, in chapters: [ComicChapterEntry]) -> Int {
        guard let position = chapters.firstIndex(where: { $0.index == index }),
              chapters[position].isSection else { return index }
        if let next = chapters[(position + 1)...].first(where: { !$0.isSection }) {
            return next.index
        }
        if let previous = chapters[..<position].last(where: { !$0.isSection }) {
            return previous.index
        }
        return index
    }

    /// Chương thường liền trước (`step` = -1) / liền sau (`step` = 1) của `index`, bỏ qua dòng tiêu đề nhóm.
    static func neighborIndex(of index: Int, step: Int, in chapters: [ComicChapterEntry]) -> Int? {
        guard step != 0, let position = chapters.firstIndex(where: { $0.index == index }) else { return nil }
        var target = position + step
        while chapters.indices.contains(target) {
            if !chapters[target].isSection {
                return chapters[target].index
            }
            target += step
        }
        return nil
    }
}
