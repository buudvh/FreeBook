import SwiftUI

/// Nút bút chì của từng name (1.3.780): mở màn Sửa từ của danh sách VP/Name (`DictEntryEditSheet`, badge
/// "AI · Riêng truyện"), tra token / nghĩa gợi ý / chip theo từ điển của truyện này. "Cập nhật" sửa danh sách đang
/// duyệt **và** tin nguồn (`onEditName` ⇒ `ReaderAIFullScreenView.applyNameEdit`) nên mở lại sheet vẫn còn; chưa ghi
/// từ điển — nút "Lưu" vẫn lo việc đó.
///
/// Vế trái hiểu đúng như màn Sửa từ của từ điển:
/// - chọn cả từ gốc ⇒ sửa nghĩa mục đó;
/// - gõ lại cả từ gốc (bút chì của màn Sửa từ) ⇒ đổi khoá của mục;
/// - chọn một phần ⇒ thêm mục mới ngay dưới mục đang sửa, mục cũ giữ nguyên.
/// Khoá đích đã có trong danh sách ⇒ ghi đè nghĩa mục đó (màn Sửa từ báo trước), không tạo bản trùng.
extension ReaderAINameReviewSheet {
    static let editBadgeText = "AI · Riêng truyện"

    func editSheet(for item: AIExtractedName) -> some View {
        let sourceKey = AINameEdit.key(item.original)
        return DictEntryEditSheet(
            originalKey: item.original,
            originalValue: item.suggestedMeaning,
            dictType: .names,
            scopeBookId: bookId,
            chipBookId: bookId,
            existingValue: { key in existingMeaning(forKey: key) },
            onUpdate: { key, meaning in
                applyEdit(.update(key: sourceKey, newKey: AINameEdit.key(key), meaning: meaning))
            },
            onAddEntry: { key, meaning in
                applyEdit(.add(key: AINameEdit.key(key), meaning: meaning, anchorKey: sourceKey))
            },
            onDefinitionsChanged: { refreshDictionaryFlags() },
            badgeText: Self.editBadgeText
        )
    }

    /// Nghĩa đang có của một khoá **trong danh sách đang duyệt** — màn Sửa từ dùng để báo ghi đè.
    func existingMeaning(forKey key: String) -> String? {
        let target = AINameEdit.key(key)
        return names.first { AINameEdit.key($0.original) == target }?.suggestedMeaning
    }

    func applyEdit(_ edit: AINameEdit) {
        guard let key = edit.resultingKey, !key.isEmpty else { return }
        names = edit.applied(to: names)
        onEditName(edit)
        if edit.mayIntroduceKey { refreshDictionaryFlags() }
    }

    /// Tra lại cờ NE/VP (đã có trong Name / VP riêng của truyện) cho cả danh sách, ngoài main. Chỉ chép hai cờ:
    /// `decorateExtractedNames` còn bỏ chọn từ đã có, nhưng trạng thái chọn là của người dùng. Mục đã đổi khoá trong
    /// lúc tra ⇒ bỏ qua (lần sửa đó tự tra lại).
    func refreshDictionaryFlags() {
        let snapshot = names
        let bid = bookId
        guard !snapshot.isEmpty else { return }
        Task { @MainActor in
            let decorated = await Task.detached(priority: .userInitiated) {
                AIBookDataInspector.shared.decorateExtractedNames(names: snapshot, bookId: bid)
            }.value
            var updated = names
            for item in decorated {
                guard let index = updated.firstIndex(where: { $0.id == item.id }),
                      updated[index].original == item.original else { continue }
                updated[index].hasInBookNames = item.hasInBookNames
                updated[index].hasInBookVP = item.hasInBookVP
            }
            names = updated
        }
    }
}
