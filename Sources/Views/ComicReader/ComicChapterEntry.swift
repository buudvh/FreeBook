import Foundation

/// Một dòng mục lục của màn đọc comic, gộp từ `StoredChapterSnapshot` (đã lưu) hoặc `ChapterResult` (online).
struct ComicChapterEntry: Equatable {
    let index: Int
    let title: String
    let titleTrans: String?
    let url: String
    let host: String?

    /// Tên hiển thị: dùng `titleTrans` khi bật dịch và đã có bản dịch, còn lại là tên gốc.
    func displayTitle(translated: Bool) -> String {
        if translated, let trans = titleTrans?.trimmingCharacters(in: .whitespacesAndNewlines), !trans.isEmpty {
            return trans
        }
        return title
    }
}
