import Foundation

/// CRUD **từng rule**, đặt ngoài `QuickTranslationRuleStore.swift` để file đó không phình quá trần
/// 400 dòng của `check_architecture.py`.
///
/// Cả ba thao tác đi qua đúng `importRules(text:source:)` nên vẫn giữ nguyên bất biến của phân hệ:
/// compile **toàn bộ** file vào staging, có hard error thì **không** ghi file và **không** swap
/// snapshot (bộ đang chạy nguyên vẹn), chỉ khi sạch mới `write(options: .atomic)` rồi bump
/// `generation` + dọn cache dịch + phát đúng một `notifyDictionariesDidUpdate`.
///
/// Địa chỉ hoá **theo key** (mẫu bên trái dấu `=`), không theo số dòng: số dòng đổi sau mỗi lần
/// thêm/xoá, còn key thì không — nên không cần khoá phiên bản file (`sourceHash`) cho sheet sửa.
extension QuickTranslationRuleStore {
    /// Thêm rule mới; key đã có thì **đè nghĩa** (vế phải), giữ nguyên vị trí dòng.
    /// Máy chưa có file rule vẫn thêm được: file được tạo mới từ rule đầu tiên.
    public func addOrOverwriteRule(pattern: String, replacement: String) -> LoadOutcome {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }

        let current = currentSourceText() ?? ""
        let updated = QuickTranslationRuleFileEditor.upsert(
            pattern: key,
            replacement: replacement,
            in: current
        )
        return importRules(text: updated, source: .edited)
    }

    /// Sửa một rule. Đổi key ⇒ xử như **thêm key mới**, dòng cũ giữ nguyên — đúng ngữ nghĩa
    /// `DictionaryCache.updateKey(oldKey:newKey:newValue:type:)` của phân hệ từ điển.
    public func updateRule(oldPattern: String, newPattern: String, replacement: String) -> LoadOutcome {
        let newKey = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newKey.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }
        guard let current = currentSourceText() else {
            return .failure(message: "Chưa có bộ rule nào trên máy")
        }

        let updated = QuickTranslationRuleFileEditor.update(
            oldPattern: oldPattern,
            newPattern: newKey,
            replacement: replacement,
            in: current
        )
        return importRules(text: updated, source: .edited)
    }

    /// Xoá hẳn dòng rule khỏi file.
    public func deleteRule(pattern: String) -> LoadOutcome {
        guard let current = currentSourceText() else {
            return .failure(message: "Chưa có bộ rule nào trên máy")
        }
        guard let updated = QuickTranslationRuleFileEditor.delete(pattern: pattern, from: current) else {
            return .failure(message: "Không tìm thấy rule này trong file")
        }
        return importRules(text: updated, source: .edited)
    }
}
