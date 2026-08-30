import Foundation

/// Thao tác **hàng loạt** trên từ điển phiên âm.
///
/// Tách khỏi `TextPreprocessor.swift` vì file đó đang **đúng bằng** baseline dòng của
/// `check_architecture.py` (1121) nên không được thêm dòng nào. Vì `private` trong Swift là phạm vi
/// **file**, `wordMap`, `saveWordMapToDisk()` và hai biến cache phải là `internal` để extension này
/// thấy được — đó là thay đổi duy nhất phía file gốc, không thêm dòng.
extension TextPreprocessor {

    /// Xoá sạch danh sách phiên âm và ghi lại file rỗng. Trả về số mục đã xoá.
    ///
    /// Ghi file **rỗng** thay vì xoá file: `loadResourcesFromDisk` coi file không tồn tại là "chưa tải
    /// từ điển", còn ở đây người dùng cố ý muốn danh sách trống — hai trạng thái đó khác nhau, và một
    /// file rỗng cũng làm lượt tải lại từ HuggingFace không có gì để trộn thắng.
    @discardableResult
    func deleteAllWords() throws -> Int {
        let removed = wordMap.count
        guard removed > 0 else { return 0 }

        wordMap.removeAll()
        try saveWordMapToDisk()

        transliterationCache.removeAll()
        transliterationCacheOrder.removeAll()

        AppLogger.shared.log("🗣️ [TextPreprocessor] Đã xoá toàn bộ \(removed) mục phiên âm theo yêu cầu người dùng")
        return removed
    }
}
