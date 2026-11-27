import SwiftUI

/// Chạm thân hàng của từng name (1.3.1060; 1.3.780–1059 là nút bút chì, hàng còn ô gõ nghĩa không lưu vào tin): mở
/// màn Sửa từ của danh sách VP/Name (`DictEntryEditSheet`, badge
/// "AI · Riêng truyện"), tra token / nghĩa gợi ý / chip theo từ điển của truyện này. "Cập nhật" sửa danh sách đang
/// duyệt **và** tin nguồn (`onEditName` ⇒ `ReaderAIFullScreenView.applyNameEdit`) nên mở lại sheet vẫn còn; chưa ghi
/// từ điển — nút "Lưu" vẫn lo việc đó.
///
/// Vế trái hiểu đúng như màn Sửa từ của từ điển:
/// - chọn cả từ gốc ⇒ sửa nghĩa mục đó;
/// - gõ lại cả từ gốc (bút chì của màn Sửa từ) ⇒ đổi khoá của mục;
/// - chọn một phần ⇒ thêm mục mới ngay dưới mục đang sửa, mục cũ giữ nguyên.
/// Khoá đích đã có trong danh sách ⇒ ghi đè nghĩa mục đó (màn Sửa từ báo trước), không tạo bản trùng.
///
/// Mục mang khoá đích sau lần sửa mất cờ `isGuessedMeaning` (nhãn "đoán"): nghĩa của nó giờ do người dùng chốt.
///
/// Luồng lọc local, name không phải người: màn Sửa từ có thêm hàng **"Đuôi"** (`LocalNameFilterSuffixQuickRow`, plan
/// 2026-11-27-nghia-ten-tay-huyen mục 7); thêm / sửa đuôi xong ⇒ ghép lại nghĩa ngay các name có đuôi đó mà nghĩa vẫn do
/// máy ghép (`LocalNameFilterReviewSuffixContext.recompose`), ô nghĩa của màn Sửa từ theo nếu người dùng chưa gõ khác
/// (`followsOriginalValue`), toast "Đã thêm đuôi 街 · ghép lại N name".
extension ReaderAINameReviewSheet {
    static let editBadgeText = "AI · Riêng truyện"
    /// Badge màn Sửa từ khi mở từ luồng "Lọc name local" (danh sách có sẵn, không có tin AI nguồn).
    static let localFilterEditBadgeText = "Lọc local · Riêng truyện"

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
            badgeText: prefilledNames == nil ? Self.editBadgeText : Self.localFilterEditBadgeText,
            accessoryRows: suffixRow(for: item),
            followsOriginalValue: localSuffixContext != nil
        )
    }

    /// Hàng "Đuôi" của màn Sửa từ — chỉ luồng lọc local, name không phải người.
    private func suffixRow(for item: AIExtractedName) -> AnyView? {
        guard let context = localSuffixContext, let kind = context.suffixKind(for: item) else { return nil }
        return AnyView(LocalNameFilterSuffixQuickRow(name: item.original, kind: kind) { key, isNew in
            suffixDidSave(key: key, isNew: isNew)
        })
    }

    /// Đuôi vừa thêm / sửa ⇒ ghép lại nghĩa các name có đuôi đó (nghĩa còn do máy ghép), áp cho name chưa bị sửa trong lúc
    /// chờ; name đang mở ở màn Sửa từ cập nhật theo (`editingName` ⇒ `originalValue`). Toast số name đã ghép lại.
    func suffixDidSave(key: String, isNew: Bool) {
        guard let context = localSuffixContext else { return }
        let snapshot = names
        Task { @MainActor in
            let changes = await context.recompose(snapshot, suffix: key)
            var updated = names
            var applied = 0
            for index in updated.indices {
                guard let change = changes[updated[index].id], updated[index].suggestedMeaning == change.old else { continue }
                updated[index].suggestedMeaning = change.new
                updated[index].isGuessedMeaning = change.isGuessed
                applied += 1
            }
            if applied > 0 {
                names = updated
                if let editing = editingName, let fresh = updated.first(where: { $0.id == editing.id }) {
                    editingName = fresh
                }
            }
            ToastManager.shared.show(
                message: "\(isNew ? "Đã thêm" : "Đã lưu") đuôi \(key) · ghép lại \(applied) name",
                type: .success
            )
        }
    }

    /// Nghĩa đang có của một khoá **trong danh sách đang duyệt** — màn Sửa từ dùng để báo ghi đè.
    func existingMeaning(forKey key: String) -> String? {
        let target = AINameEdit.key(key)
        return names.first { AINameEdit.key($0.original) == target }?.suggestedMeaning
    }

    func applyEdit(_ edit: AINameEdit) {
        guard let key = edit.resultingKey, !key.isEmpty else { return }
        // Ghi `names` một lần (mỗi lần ghi là một lượt `onNamesChange` ⇒ gói tạm).
        var updated = edit.applied(to: names)
        // Bỏ nhãn "đoán" của mục vừa nhận nghĩa từ màn Sửa từ. Chọn một phần ⇒ mục mới (cờ mặc định tắt), mục gốc giữ cờ.
        let editedKey = AINameEdit.key(key)
        if let index = updated.firstIndex(where: { AINameEdit.key($0.original) == editedKey }) {
            updated[index].isGuessedMeaning = false
        }
        names = updated
        onEditName(edit)
        // Sửa một name thành khoá đang gạch ⇒ người dùng muốn dùng khoá đó: bỏ gạch, kẻo nghĩa mới nằm trong hàng gạch
        // (không chọn / không lưu được).
        let normalizedKey = AIRuntimeCoordinator.nameKey(key)
        if prefilledNames == nil, struckKeys.contains(normalizedKey) {
            struckKeys.remove(normalizedKey)
            onStrikeName(normalizedKey, false)
        }
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
