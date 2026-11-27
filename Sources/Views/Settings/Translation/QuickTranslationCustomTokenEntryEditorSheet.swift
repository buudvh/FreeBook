import SwiftUI

/// Sheet thêm / sửa **một từ** của token tùy chọn `<@tên>` = màn **Sửa từ** của từ điển (`DictEntryEditSheet` chế độ danh
/// sách, plan 2026-11-27 — anh Bửu: danh sách vế trái chữ Hán làm kiểu Sửa từ; trước đó là form hai ô của 1.3.1063):
/// badge "<@tên> · Chung", hàng chữ gốc chọn được, hàng token, **ô nghĩa = nghĩa của từ** (`{i}` khi khớp), chip nghĩa
/// gợi ý, aa…AA. Chỗ trình bày bọc `Group { … }.appGlassSheet()`.
///
/// Luật lấy từ `QuickTranslationCustomTokenStore` (`keyError` / `meaningError` — cùng luật với nhập file), hiện đỏ ở dòng
/// thông báo; ô còn trống thì không tô đỏ. Chọn cả từ (kể cả gõ lại bằng bút chì) ⇒ sửa / đổi chữ gốc của mục đang sửa;
/// chọn một phần ⇒ thêm từ mới = phần đang chọn, từ đang sửa giữ nguyên. Ghi do màn danh sách làm (`onSave` trả chuỗi lỗi
/// nếu không lưu được — sheet giữ nguyên để sửa tiếp).
struct QuickTranslationCustomTokenEntryEditorSheet: View {
    typealias Entry = QuickTranslationCustomToken.Entry
    typealias Store = QuickTranslationCustomTokenStore

    let tokenName: String
    /// `nil` = thêm từ mới.
    let original: Entry?
    /// `replacing` = chữ gốc bị thay (`nil` = thêm mới, kể cả thêm phần chọn một phần khi đang sửa).
    let onSave: (_ key: String, _ meaning: String, _ replacing: String?) -> String?

    init(
        tokenName: String,
        original: Entry?,
        onSave: @escaping (_ key: String, _ meaning: String, _ replacing: String?) -> String?
    ) {
        self.tokenName = tokenName
        self.original = original
        self.onSave = onSave
    }

    var body: some View {
        DictEntryEditSheet(
            originalKey: original?.key ?? "",
            originalValue: original?.meaning ?? "",
            dictType: .vietPhrase, // chỉ nuôi badge mặc định — `badgeText` thay
            scopeBookId: nil,
            chipBookId: nil,
            existingValue: { key in
                Store.shared.token(named: tokenName)?.entries.first { $0.key == key }?.meaning
            },
            onUpdate: { _, _ in },
            onAddEntry: { _, _ in },
            onDefinitionsChanged: {},
            badgeText: "<@\(tokenName)> · Chung",
            listMode: DictEntryEditListMode(
                keyError: { key, replacing in Store.shared.keyError(key, in: tokenName, replacing: replacing) },
                meaningError: { meaning in Store.shared.meaningError(meaning) },
                save: { key, meaning, replacing in onSave(key, meaning, replacing) }
            )
        )
    }
}
