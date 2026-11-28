import Foundation

/// **"Nhập file"** của màn Không phải name, danh sách **Chung** (ngăn kéo `…`, anh Bửu 2026-11-28). File cùng định dạng
/// "Xuất file": mỗi dòng một cụm chữ Hán, dòng trống / dòng `#` bỏ qua, cụm sai luật (`formatError`) bị bỏ và đếm
/// (`LocalNameFilterListImport.termFile`).
/// - **Gộp** và **Chỉ thêm key mới** (danh sách chỉ có khoá ⇒ cùng kết quả): cụm đã có giữ nguyên (cả ngày thêm), cụm mới
///   thêm vào.
/// - **Thay thế toàn bộ**: danh sách thành đúng các cụm của file; cụm vốn có giữ ngày thêm cũ.
/// Nhập xong mà vượt trần `maxCount` cụm ⇒ lỗi, không ghi gì. Một lần nhập = **một** lần ghi `UserDefaults`; gọi từ main
/// như mọi lệnh ghi khác của store này.
extension LocalNameFilterBlocklistStore {
    func importFile(at url: URL, mode: DataImportMode) -> LocalNameFilterListImport.ImportResult {
        let file: LocalNameFilterListImport.TermFile
        switch LocalNameFilterListImport.termFile(at: url) {
        case .success(let parsed): file = parsed
        case .failure(let failure): return .failure(failure)
        }

        let current = LocalNameFilterBlocklistStore.load()
        let merged = LocalNameFilterListImport.mergeTerms(current: current, terms: file.terms, mode: mode)
        guard merged.items.count <= LocalNameFilterBlocklistStore.maxCount else {
            return .failure(LocalNameFilterListImport.tooManyTerms(merged.items.count))
        }
        if merged.items != current, let error = LocalNameFilterBlocklistStore.save(merged.items) {
            return .failure(LocalNameFilterListImport.Failure(message: error))
        }
        return .success(merged.outcome(skipped: file.skipped))
    }
}
