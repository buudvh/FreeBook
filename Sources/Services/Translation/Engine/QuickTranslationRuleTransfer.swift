import Foundation

/// Chuyển một rule sang phạm vi khác (riêng / tên chương / chung), và chia sẻ cả bộ rule riêng sang truyện khác.
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
        case .chapterTitle:
            return QuickTranslationRuleChapterStore.shared.addOrOverwriteRule(
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

    /// Các phạm vi đích cho nút Chuyển của một rule đang đứng ở `scope`, theo thứ tự ưu tiên
    /// riêng → tên chương → chung và **không** gồm chính `scope`. Bộ riêng chỉ có mặt khi biết truyện đang
    /// mở (`contextBookId`) và rule không sẵn ở một bộ riêng — chia sẻ giữa các truyện đi lối
    /// `shareBookRules`. Mảng rỗng = không xác định được đích ⇒ UI làm mờ nút Chuyển và chỉ báo lý do,
    /// tuyệt đối không ghi bừa.
    public static func transferTargets(
        of scope: QuickTranslationRuleScope,
        contextBookId: String?
    ) -> [QuickTranslationRuleScope] {
        var targets: [QuickTranslationRuleScope] = []
        if scope.bookId == nil, let contextBookId, !contextBookId.isEmpty {
            targets.append(.book(contextBookId))
        }
        targets += [QuickTranslationRuleScope.chapterTitle, .global].filter { $0 != scope }
        return targets
    }

    /// Chia sẻ **cả bộ rule riêng** của một truyện sang truyện khác.
    ///
    /// Chia sẻ đi qua `QuickTranslationRuleBookStore.importRules`, nơi trộn records rồi ghi lại file
    /// canonical. Thứ tự file đích làm xương sống; mẫu mới từ file nguồn được nối cuối.
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
