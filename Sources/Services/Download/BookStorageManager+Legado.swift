import Foundation

/// Dọn trạng thái theo truyện của nguồn Legado khi xoá sách. Tách khỏi `BookStorageManager.swift` (sát giới hạn
/// 400 dòng).
extension BookStorageManager {
    /// File `legado_state/<sha256(bookId)>.json` (biến, `tocUrl`… của truyện) — chủ là `LegadoBookStateStore`, tự kiểm
    /// `validatePathSafety`. Sách của tiện ích JS không có file này nên là no-op. Gọi **sau** khi DB đã lưu thành công,
    /// cùng chỗ với các file vật lý khác của truyện.
    /// Lỗi xoá do `LegadoBookStateStore` tự ghi log `❌`; ở đây chỉ cần gọi.
    nonisolated static func deleteLegadoState(bookId: String) async {
        _ = LegadoBookStateStore.deleteState(bookId: bookId)
    }
}
