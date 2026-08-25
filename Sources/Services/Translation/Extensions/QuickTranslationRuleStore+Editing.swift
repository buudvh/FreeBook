import Foundation

/// CRUD **từng rule**, đặt ngoài `QuickTranslationRuleStore.swift` để file đó không phình quá trần
/// 400 dòng của `check_architecture.py`.
///
/// Cả ba thao tác đi qua cùng validate-then-swap nên vẫn giữ nguyên bất biến của phân hệ:
/// compile **toàn bộ** file vào staging, có hard error thì **không** ghi file và **không** swap
/// snapshot (bộ đang chạy nguyên vẹn), chỉ khi sạch mới `write(options: .atomic)` rồi bump
/// `generation` + dọn cache dịch + phát đúng một `notifyDictionariesDidUpdate`.
///
/// Thêm/sửa vẫn theo key (mẫu bên trái dấu `=`). Riêng xoá nhận handle UUID của đúng hàng; Store kiểm
/// revision toàn file rồi mới dùng `sourceLine` như toạ độ tạm thời để FileEditor xác minh cả mẫu lẫn vế phải.
extension QuickTranslationRuleStore {
    /// Thêm rule mới; key đã có thì **đè nghĩa** (vế phải), giữ nguyên vị trí dòng.
    /// Máy chưa có file rule vẫn thêm được: file được tạo mới từ rule đầu tiên.
    public func addOrOverwriteRule(pattern: String, replacement: String) -> LoadOutcome {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }

        return withMutationLock {
            let edit = QuickTranslationRuleFileEditor.upsert(
                pattern: key,
                replacement: replacement,
                in: currentSourceText() ?? ""
            )
            return importRulesLocked(text: edit.text, source: .edited, edit: edit)
        }
    }

    /// Sửa một rule. Đổi key ⇒ xử như **thêm key mới**, dòng cũ giữ nguyên — đúng ngữ nghĩa
    /// `DictionaryCache.updateKey(oldKey:newKey:newValue:type:)` của phân hệ từ điển.
    public func updateRule(oldPattern: String, newPattern: String, replacement: String) -> LoadOutcome {
        let newKey = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newKey.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }
        return withMutationLock {
            guard let current = currentSourceText() else {
                return .failure(message: "Chưa có bộ rule nào trên máy")
            }
            let edit = QuickTranslationRuleFileEditor.update(
                oldPattern: oldPattern,
                newPattern: newKey,
                replacement: replacement,
                in: current
            )
            return importRulesLocked(text: edit.text, source: .edited, edit: edit)
        }
    }

    /// Xoá hẳn đúng hàng đã vuốt, kể cả khi file có nhiều rule trùng hoàn toàn mẫu/bản dịch.
    public func deleteRule(rowID: UUID) -> LoadOutcome {
        withMutationLock {
            guard let snapshot = currentSnapshot,
                  let current = currentSourceText() else {
                return .failure(message: "Bộ rule đã thay đổi, hãy tải lại danh sách rồi thử lại")
            }
            guard current.sha256() == snapshot.sourceRevision else {
                return .failure(message: "Bộ rule đã thay đổi ngoài app, hãy tải lại danh sách rồi thử lại")
            }
            guard let row = snapshot.rows.first(where: { $0.id == rowID }),
                  snapshot.rules.indices.contains(row.ruleIndex) else {
                return .failure(message: "Rule đã không còn trong danh sách hiện tại")
            }

            let rule = snapshot.rules[row.ruleIndex]
            guard let edit = QuickTranslationRuleFileEditor.delete(
                sourceLine: rule.sourceLine,
                expectedPattern: rule.pattern,
                expectedReplacement: rule.replacement,
                from: current
            ) else {
                return .failure(message: "Không tìm thấy đúng rule đã chọn trong file")
            }
            return importRulesLocked(text: edit.text, source: .edited, edit: edit)
        }
    }

    /// Chỉ CRUD tay mới truyền `edit`; nhập/tải/khôi phục thay dataset nên nhận UUID mới toàn bộ.
    static func rowIDs(
        for rules: [QuickTranslationCompiledRule],
        previousSnapshot: QuickTranslationRuleSnapshot?,
        edit: QuickTranslationRuleFileEditor.Edit?
    ) -> [UUID] {
        guard let previousSnapshot, let edit else { return rules.map { _ in UUID() } }

        var identifiers: [Int: UUID] = [:]
        var previousRules: [Int: QuickTranslationCompiledRule] = [:]
        for row in previousSnapshot.rows where previousSnapshot.rules.indices.contains(row.ruleIndex) {
            let rule = previousSnapshot.rules[row.ruleIndex]
            identifiers[rule.sourceLine] = row.id
            previousRules[rule.sourceLine] = rule
        }

        return rules.map { rule in
            guard let previousLine = previousSourceLine(for: rule.sourceLine, edit: edit.kind),
                  let identifier = identifiers[previousLine],
                  let previousRule = previousRules[previousLine],
                  retainsRowID(previous: previousRule, next: rule, edit: edit.kind) else {
                return UUID()
            }
            return identifier
        }
    }

    private static func previousSourceLine(
        for sourceLine: Int,
        edit: QuickTranslationRuleFileEditor.Edit.Kind
    ) -> Int? {
        switch edit {
        case .inserted(let changedLine):
            guard sourceLine != changedLine else { return nil }
            return sourceLine > changedLine ? sourceLine - 1 : sourceLine
        case .deleted(let changedLine, _, _):
            return sourceLine >= changedLine ? sourceLine + 1 : sourceLine
        case .replaced(_, _, _), .unchanged:
            return sourceLine
        }
    }

    private static func retainsRowID(
        previous: QuickTranslationCompiledRule,
        next: QuickTranslationCompiledRule,
        edit: QuickTranslationRuleFileEditor.Edit.Kind
    ) -> Bool {
        if case let .replaced(changedLine, previousPattern, previousReplacement) = edit,
           next.sourceLine == changedLine {
            return previous.pattern == previousPattern && previous.replacement == previousReplacement
        }
        return previous.pattern == next.pattern && previous.replacement == next.replacement
    }
}
