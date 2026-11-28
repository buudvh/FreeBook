import Foundation

/// **"Nhập file"** của màn Hậu tố / Tiền tố (ngăn kéo `…`, anh Bửu 2026-11-28) — nhập vào đúng danh sách của chip phạm vi
/// đang chọn. File cùng định dạng "Xuất file" (`chữ Hán=nghĩa|loại|vị trí[|off]`), đọc + kiểm bằng
/// `LocalNameFilterSuffixListParser` (`LocalNameFilterListImport.affixFile`). Một lần nhập = **một** lần ghi `UserDefaults`.
///
/// Danh sách **Chung** là "file gốc trong bundle + lớp sửa đổi" ⇒ ba chế độ trộn trên lớp sửa đổi
/// (`LocalNameFilterSuffixOverrides.importLines`): "Thay thế toàn bộ" đưa mục gốc vắng trong file vào `removed`, mục trùng
/// y bản gốc không ghi vào `entries`. Danh sách **Riêng truyện** là mảng ⇒ `LocalNameFilterBookAffixStore.importFile`.
///
/// Không đi vào bộ dịch ⇒ nhập xong không dọn cache dịch / báo rule đổi. Store không phát thay đổi ⇒ màn tự đọc lại.
extension LocalNameFilterAffixListStore {
    /// Nhập file vào danh sách của phạm vi `scope` (`bookId` chỉ dùng khi `scope == .book`). File không đọc được / không
    /// có dòng hợp lệ / không ghi được ⇒ `.failure`, danh sách giữ nguyên.
    func importFile(
        at url: URL,
        mode: DataImportMode,
        scope: Scope,
        bookId: String
    ) -> LocalNameFilterListImport.ImportResult {
        switch scope {
        case .common: return importFile(at: url, mode: mode)
        case .book: return bookStore.importFile(at: url, mode: mode, bookId: bookId)
        }
    }

    /// Nhập file vào danh sách **Chung** (mọi truyện).
    func importFile(at url: URL, mode: DataImportMode) -> LocalNameFilterListImport.ImportResult {
        let file: LocalNameFilterListImport.AffixFile
        switch LocalNameFilterListImport.affixFile(at: url, noun: noun) {
        case .success(let parsed): file = parsed
        case .failure(let failure): return .failure(failure)
        }

        let before = currentOverrides()
        var overrides = before
        let counts = overrides.importLines(file.lines, mode: mode, base: base)
        // File trùng y danh sách đang có ⇒ không có gì để ghi.
        if overrides != before, let error = write(overrides) {
            return .failure(LocalNameFilterListImport.Failure(message: error))
        }
        return .success(LocalNameFilterListImport.Outcome(
            added: counts.added, updated: counts.updated, removed: counts.removed, skipped: file.skipped
        ))
    }
}
