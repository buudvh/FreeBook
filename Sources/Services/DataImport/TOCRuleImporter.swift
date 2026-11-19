import Foundation

/// Áp danh sách **quy tắc mục lục (TOC)** vừa đọc từ file JSON lên danh sách hiện có theo ba `DataImportMode`.
///
/// Khoá so trùng = `id` của quy tắc (đã bỏ khoảng trắng hai đầu; `TranslateUtils.validateImportedTOCRules` đã chặn
/// `id` lặp trong file). Dùng lại đúng các hàm của `TranslateUtils` (chuẩn hoá chữ giống hệt đường sao lưu):
/// - `.replaceAll` ⇒ `replaceTOCRules`: thay bằng danh sách trong file **và tự thêm lại quy tắc mặc định bị thiếu**
///   (quy tắc mặc định không xoá được ở màn này — giữ hành vi "Thay thế toàn bộ" cũ).
/// - `.overwriteExisting` ⇒ `mergeTOCRules`: `id` trùng thì thay tại chỗ, `id` mới nối cuối (= "Gộp theo ID" cũ).
/// - `.keepExisting` ⇒ `mergeTOCRules` chỉ với các quy tắc có `id` chưa có trên máy.
///
/// Hàm thuần, không ghi đĩa — màn gọi tự lưu qua `TOCRuleSaveCoordinator` như mọi thao tác khác của màn.
enum TOCRuleImporter {
    static func apply(
        _ imported: [TOCRule],
        to current: [TOCRule],
        mode: DataImportMode
    ) -> (rules: [TOCRule], summary: KeyedImportSummary) {
        let currentIDs = Set(current.map(\.id))
        let trimmedID: (TOCRule) -> String = { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }

        switch mode {
        case .replaceAll:
            let rules = TranslateUtils.replaceTOCRules(imported: imported)
            let summary = KeyedImportSummary(
                mode: mode,
                importedCount: imported.count,
                previousCount: current.count,
                totalCount: rules.count
            )
            return (rules, summary)

        case .overwriteExisting:
            let rules = TranslateUtils.mergeTOCRules(current: current, imported: imported)
            let matched = imported.filter { currentIDs.contains(trimmedID($0)) }.count
            // `mergeTOCRules` thay tại chỗ ⇒ phần đầu kết quả cùng vị trí với danh sách cũ.
            let changed = zip(current, rules).filter { pair in pair.0 != pair.1 }.count
            let summary = KeyedImportSummary(
                mode: mode,
                importedCount: imported.count,
                added: rules.count - current.count,
                updated: changed,
                unchanged: max(0, matched - changed),
                previousCount: current.count,
                totalCount: rules.count
            )
            return (rules, summary)

        case .keepExisting:
            let fresh = imported.filter { !currentIDs.contains(trimmedID($0)) }
            let rules = TranslateUtils.mergeTOCRules(current: current, imported: fresh)
            let summary = KeyedImportSummary(
                mode: mode,
                importedCount: imported.count,
                added: rules.count - current.count,
                skipped: imported.count - fresh.count,
                previousCount: current.count,
                totalCount: rules.count
            )
            return (rules, summary)
        }
    }
}
