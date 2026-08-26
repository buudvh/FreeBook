import Foundation

/// CRUD **từng rule**, đặt ngoài `QuickTranslationRuleStore.swift` để file đó không phình quá trần
/// 400 dòng của `check_architecture.py`.
///
/// Cả ba thao tác đi qua cùng một luồng records như VP/Name custom: đọc TXT, bỏ dòng không hợp lệ,
/// trùng mẫu lấy dòng đầu, sửa mảng records rồi ghi lại một file `pattern = replacement` sạch.
///
/// Thêm/sửa/xoá đều theo key nghiệp vụ là mẫu bên trái dấu `=`; `sourceLine` chỉ còn là thứ tự ưu tiên
/// sau khi compile lại, không dùng để định danh thao tác.
extension QuickTranslationRuleStore {
    /// Thêm rule mới; key đã có thì **đè nghĩa** (vế phải), giữ nguyên vị trí dòng.
    /// Máy chưa có file rule vẫn thêm được: file được tạo mới từ rule đầu tiên.
    public func addOrOverwriteRule(pattern: String, replacement: String) -> LoadOutcome {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }

        return withMutationLock {
            let records = QuickTranslationRuleRecordStore.upsert(
                pattern: key,
                replacement: replacement,
                in: QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText() ?? "")
            )
            return writeRecordsLocked(records, source: .edited)
        }
    }

    /// Sửa một rule. Đổi key ⇒ xử như **thêm key mới**, dòng cũ giữ nguyên — đúng ngữ nghĩa
    /// `DictionaryCache.updateKey(oldKey:newKey:newValue:type:)` của phân hệ từ điển.
    public func updateRule(oldPattern _: String, newPattern: String, replacement: String) -> LoadOutcome {
        let newKey = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newKey.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }
        return withMutationLock {
            let records = QuickTranslationRuleRecordStore.upsert(
                pattern: newKey,
                replacement: replacement,
                in: QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText() ?? "")
            )
            return writeRecordsLocked(records, source: .edited)
        }
    }

    /// Xoá hẳn rule theo mẫu bên trái dấu `=`. File được chuẩn hoá first-wins nên key này là duy nhất.
    public func deleteRule(pattern: String) -> LoadOutcome {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }
        return withMutationLock {
            let current = currentSourceText() ?? ""
            let records = QuickTranslationRuleRecordStore.parseRecords(from: current)
            let updated = QuickTranslationRuleRecordStore.removing(pattern: key, from: records)
            guard updated.count != records.count else {
                return .failure(message: "Không tìm thấy đúng rule đã chọn trong file")
            }
            return writeRecordsLocked(updated, source: .edited)
        }
    }
}
