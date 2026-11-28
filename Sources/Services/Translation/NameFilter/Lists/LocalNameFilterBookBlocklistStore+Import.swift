import Foundation

/// **"Nhập file"** của màn Không phải name, danh sách **Riêng truyện** (chip "Riêng truyện", anh Bửu 2026-11-28). Cùng
/// định dạng + luật trộn với danh sách Chung (`LocalNameFilterBlocklistStore.importFile`): Gộp / Chỉ thêm key mới = thêm cụm
/// chưa có, Thay thế toàn bộ = danh sách riêng của truyện thành đúng các cụm của file; cụm vốn có giữ ngày thêm cũ. "Đã có"
/// chỉ xét trong danh sách riêng của **chính truyện này** (hai danh sách Chung / Riêng độc lập). Trần `maxCount` cụm mỗi
/// truyện: vượt ⇒ lỗi, không ghi gì. Đọc – trộn – ghi **một lần** dưới `lock` của store.
extension LocalNameFilterBookBlocklistStore {
    func importFile(at url: URL, mode: DataImportMode, bookId: String) -> LocalNameFilterListImport.ImportResult {
        guard !bookId.isEmpty else {
            return .failure(LocalNameFilterListImport.Failure(message: LocalNameFilterBookBlocklistStore.noBookError))
        }
        let file: LocalNameFilterListImport.TermFile
        switch LocalNameFilterListImport.termFile(at: url) {
        case .success(let parsed): file = parsed
        case .failure(let failure): return .failure(failure)
        }

        lock.lock()
        defer { lock.unlock() }
        var table = currentTable()
        let current = table[bookId] ?? []
        let merged = LocalNameFilterListImport.mergeTerms(current: current, terms: file.terms, mode: mode)
        guard merged.items.count <= LocalNameFilterBookBlocklistStore.maxCount else {
            return .failure(LocalNameFilterListImport.tooManyTerms(merged.items.count))
        }
        if merged.items != current {
            table[bookId] = merged.items
            if let error = write(table) { return .failure(LocalNameFilterListImport.Failure(message: error)) }
        }
        return .success(merged.outcome(skipped: file.skipped))
    }
}
