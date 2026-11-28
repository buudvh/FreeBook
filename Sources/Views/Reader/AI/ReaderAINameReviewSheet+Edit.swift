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
/// Luồng lọc local, mọi loại name trừ họ tộc: màn Sửa từ có thêm khối hàng phụ `LocalNameFilterReviewAffixRows` — hàng
/// **"Phân loại"** (2026-11-28, mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2) rồi **"Tiền tố"** (nút ⚙ ⇒
/// màn Quản lý tiền tố, hậu tố) và **"Hậu tố"** (`LocalNameFilterSuffixQuickRow`, plan 2026-11-27-nghia-ten-tay-huyen mục 7,
/// 2026-11-27-phan-loai-name mục 7 / 10 / L10 / L11); thêm / sửa / xoá một mục xong ⇒ ghép lại nghĩa ngay các name kết thúc
/// bằng hậu tố / mở đầu bằng tiền tố đó mà nghĩa vẫn do máy ghép (`LocalNameFilterReviewSuffixContext.recompose`), ô nghĩa
/// của màn Sửa từ theo nếu người dùng chưa gõ khác (`followsOriginalValue`), toast "Đã thêm hậu tố 街 · ghép lại N name".
/// Đổi Phân loại ⇒ badge + số chip lọc đổi ngay, nghĩa ghép lại theo nhóm mới nếu chưa sửa tay (`changeCategory`).
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
            accessoryRows: affixRows(for: item),
            followsOriginalValue: localSuffixContext != nil
        )
    }

    /// Khối "Phân loại" + "Tiền tố" + "Hậu tố" của màn Sửa từ (mockup M2: phân loại trên cùng, tiền tố, hậu tố) — chỉ luồng
    /// lọc local, mọi loại name trừ họ tộc. `item` là bản mới nhất (`editingName`) ⇒ đổi Phân loại là hàng gợi ý theo loại mới.
    private func affixRows(for item: AIExtractedName) -> AnyView? {
        guard let context = localSuffixContext, let kind = context.affixKind(for: item) else { return nil }
        let itemId = item.id
        return AnyView(LocalNameFilterReviewAffixRows(
            name: item.original,
            bookId: context.bookId,
            kind: kind,
            category: LocalNameFilterCategoryBadge.category(forLabel: item.category),
            originalCategory: context.originalCategory(of: item.original),
            onCategoryChange: { category in changeCategory(of: itemId, to: category) },
            onAffixChanged: { flavor, key, replaced, verb in
                affixDidSave(flavor, key: key, replaced: replaced, verb: verb)
            }
        ))
    }

    /// Đổi Phân loại (hàng "Phân loại", hợp đồng lõi mục 7): đổi nhãn badge **ngay** (số trên chip lọc theo, hàng Tiền tố /
    /// Hậu tố gợi ý loại mới, gói tạm nhận `names` mới), nhớ nhóm lúc lọc cho dòng "Lúc lọc: …", rồi xếp `changeKind` vào hàng
    /// đợi của ngữ cảnh: nghĩa máy + loại trong gói tạm theo nhóm mới; nghĩa chưa sửa tay thì ghép lại và áp lên hàng nếu nó
    /// vẫn là nghĩa cũ (người dùng chưa sửa trong lúc chờ). Không nhớ cho lần lọc sau.
    func changeCategory(of itemId: UUID, to category: LocalNameFilter.Category) {
        guard let context = localSuffixContext, let index = names.firstIndex(where: { $0.id == itemId }) else { return }
        let term = names[index].original
        let previous = LocalNameFilterCategoryBadge.category(forLabel: names[index].category)
        guard previous != category else { return }
        context.rememberOriginalCategory(previous, of: term)
        names[index].category = category.label
        if editingName?.id == itemId { editingName = names[index] }
        let kind = LocalNameFilterLACPipeline.kind(for: category)
        Task { @MainActor in
            context.changeKind(of: term, itemId: itemId, to: kind, currentNames: { names }) { change in
                guard let current = names.firstIndex(where: { $0.id == itemId }),
                      names[current].suggestedMeaning == change.old else { return }
                var updated = names
                updated[current].suggestedMeaning = change.new
                updated[current].isGuessedMeaning = change.isGuessed
                names = updated
                if editingName?.id == itemId { editingName = updated[current] }
            }
        }
    }

    /// Hậu tố / tiền tố vừa thêm / sửa / xoá ⇒ ghép lại nghĩa các name kết thúc / mở đầu bằng nó (nghĩa còn do máy ghép), áp
    /// cho name chưa bị sửa trong lúc chờ; name đang mở ở màn Sửa từ cập nhật theo (`editingName` ⇒ `originalValue`). Toast
    /// "<verb> hậu tố X · ghép lại N name" (verb: "Đã thêm" / "Đã lưu" / "Đã xoá"). Sửa mục có sẵn mà đổi chữ (`replaced`) ⇒
    /// ghép lại cả name mang khoá cũ (nghĩa của chúng dựa vào mục vừa mất). Lượt thứ hai chạy sau lượt đầu nên name mang cả
    /// hai khoá chỉ đổi một lần (`recompose` so với nghĩa máy ghép mới nhất).
    func affixDidSave(_ flavor: LocalNameFilterAffixListFlavor, key: String, replaced: String?, verb: String) {
        guard let context = localSuffixContext else { return }
        let affixes = [key] + (replaced.map { $0 == key ? [] : [$0] } ?? [])
        // Xếp hàng trong `context`: lưu hai mục liền nhau ⇒ lượt sau đọc `names` đã áp lượt trước. Nhảy sang main-actor
        // tường minh như bản trước (hàm này có thể được coi là nonisolated tuỳ phiên bản SDK).
        Task { @MainActor in context.enqueueRecompose(affixes: affixes, flavor: flavor, currentNames: { names }) { changes in
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
                message: "\(verb) \(flavor.lowercasedNoun) \(key) · ghép lại \(applied) name",
                type: .success
            )
        } }
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
