import Foundation

/// Chuyển một rule sang phạm vi còn lại, và chia sẻ cả bộ rule riêng sang truyện khác.
///
/// **Là COPY, không phải MOVE** — đúng như nút Chuyển của từ điển (xem doc đầu `DictionaryEntryRow`):
/// rule ở phạm vi nguồn **giữ nguyên**, phạm vi đích nhận thêm; trùng mẫu ở đích thì **đè vế phải**
/// (ngữ nghĩa `addOrOverwriteRule`). Người dùng muốn bỏ bản nguồn thì xoá tay — không tự xoá hộ.
public enum QuickTranslationRuleTransfer {

    /// Copy đúng một rule sang phạm vi `destination`.
    public static func copy(
        pattern: String,
        replacement: String,
        to destination: QuickTranslationRuleScope
    ) -> QuickTranslationRuleStore.LoadOutcome {
        switch destination {
        case .global:
            return QuickTranslationRuleStore.shared.addOrOverwriteRule(
                pattern: pattern,
                replacement: replacement
            )
        case .book(let bookId):
            return QuickTranslationRuleBookStore.shared.addOrOverwriteRule(
                pattern: pattern,
                replacement: replacement,
                bookId: bookId
            )
        }
    }

    /// Phạm vi đối diện của một rule đang đứng ở `scope`, có `contextBookId` là truyện đang mở.
    /// `nil` = không xác định được đích (đang ở danh sách Chung mà không biết truyện nào) ⇒ UI phải
    /// làm mờ nút Chuyển và chỉ báo lý do, tuyệt đối không ghi bừa.
    public static func opposite(
        of scope: QuickTranslationRuleScope,
        contextBookId: String?
    ) -> QuickTranslationRuleScope? {
        switch scope {
        case .global:
            guard let contextBookId, !contextBookId.isEmpty else { return nil }
            return .book(contextBookId)
        case .book:
            return .global
        }
    }

    /// Chia sẻ **cả bộ rule riêng** của một truyện sang truyện khác.
    ///
    /// Hàm trộn là `QuickTranslationRuleFileEditor.merge` chứ **không** phải
    /// `DictionaryTextFileStore.mergedRecords` như từ điển: primitive của từ điển sinh lại file từ
    /// danh sách `key=value` nên mất comment và **xáo thứ tự dòng** — mà thứ tự dòng là tie-break cuối
    /// của priority rule.
    public static func shareBookRules(
        from sourceBookId: String,
        to targetBookId: String,
        mode: DataImportMode
    ) -> QuickTranslationRuleStore.LoadOutcome {
        guard sourceBookId != targetBookId else {
            return .failure(message: "Truyện nguồn và truyện đích trùng nhau")
        }
        guard let text = QuickTranslationRuleBookStore.shared.currentSourceText(for: sourceBookId),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(message: "Truyện này chưa có bộ rule riêng để chia sẻ")
        }
        return QuickTranslationRuleBookStore.shared.importRules(
            text: text,
            mode: mode,
            bookId: targetBookId
        )
    }
}
