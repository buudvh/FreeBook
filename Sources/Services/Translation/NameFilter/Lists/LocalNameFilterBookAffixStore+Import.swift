import Foundation

/// **"Nhập file"** vào danh sách Hậu tố / Tiền tố **riêng truyện** (chip "Riêng truyện" của màn danh sách, anh Bửu
/// 2026-11-28) — gọi qua `LocalNameFilterAffixListStore.importFile(at:mode:scope:bookId:)`. Cùng định dạng + bộ đọc với danh
/// sách Chung; danh sách riêng là mảng nên trộn bằng `LocalNameFilterListImport.merge`:
/// - **Gộp**: chữ đã có ⇒ đè nghĩa / loại / vị trí tại chỗ (chỉ tính "cập nhật" khi thực sự khác); chữ mới đứng đầu.
/// - **Chỉ thêm key mới**: chữ đã có giữ nguyên; chữ mới đứng đầu.
/// - **Thay thế toàn bộ**: danh sách riêng của truyện thành đúng nội dung file (theo thứ tự file).
/// "Đã có" chỉ xét trong danh sách riêng của **chính truyện này** — cùng chữ với một mục Chung thì vẫn thêm (bản Riêng
/// thắng ở danh sách hiệu lực). Đọc – trộn – ghi **một lần** dưới `lock` của store.
extension LocalNameFilterBookAffixStore {
    func importFile(at url: URL, mode: DataImportMode, bookId: String) -> LocalNameFilterListImport.ImportResult {
        guard !bookId.isEmpty else {
            return .failure(LocalNameFilterListImport.Failure(message: "Không có truyện để lưu \(noun.lowercased()) riêng."))
        }
        let file: LocalNameFilterListImport.AffixFile
        switch LocalNameFilterListImport.affixFile(at: url, noun: noun) {
        case .success(let parsed): file = parsed
        case .failure(let failure): return .failure(failure)
        }
        let imported = file.lines.map {
            StoredItem(key: $0.key, meaning: $0.value.meaning, kind: $0.value.kind, position: $0.value.position)
        }

        lock.lock()
        defer { lock.unlock() }
        var table = currentTable()
        let current = table[bookId] ?? []
        let merged = LocalNameFilterListImport.merge(current: current, imported: imported, mode: mode) { $0.key }
        if merged.items != current {
            table[bookId] = merged.items
            if let error = write(table) { return .failure(LocalNameFilterListImport.Failure(message: error)) }
        }
        return .success(merged.outcome(skipped: file.skipped))
    }
}
