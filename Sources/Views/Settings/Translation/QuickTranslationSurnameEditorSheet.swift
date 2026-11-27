import SwiftUI

/// Sheet thêm / sửa **một** họ của màn Danh sách họ = màn **Sửa từ** của từ điển (`DictEntryEditSheet` chế độ danh sách,
/// plan 2026-11-27 — anh Bửu: danh sách vế trái chữ Hán làm kiểu Sửa từ; trước đó là form hai ô của 1.3.1062): badge
/// "Họ · Chung", hàng chữ gốc chọn được, hàng token, **ô nghĩa = âm Hán-Việt của họ**, chip nghĩa gợi ý, aa…AA. Chỗ trình
/// bày bọc `Group { … }.appGlassSheet()`.
///
/// - Luật lấy từ `QuickTranslationSurnameStore` (`keyError` / `readingError` — cùng luật với nhập file), hiện đỏ ở dòng
///   thông báo; ô còn trống thì không tô đỏ. Đổi chữ gốc = xoá khoá cũ + thêm khoá mới (store lo); chọn một phần (vd 欧
///   của 欧阳) ⇒ thêm họ mới = phần đang chọn, họ đang sửa giữ nguyên.
/// - Ghi do màn danh sách làm (`onSave` trả chuỗi lỗi nếu không lưu được — sheet giữ nguyên để sửa tiếp).
/// - Họ gốc đã đổi âm có thêm nút "Về âm gốc: …".
struct QuickTranslationSurnameEditorSheet: View {
    typealias Entry = QuickTranslationSurnameEntry

    /// `nil` = thêm họ mới.
    let original: Entry?
    /// `replacing` = khoá bị thay (`nil` = thêm mới, kể cả thêm phần chọn một phần khi đang sửa).
    let onSave: (_ key: String, _ reading: String, _ replacing: String?) -> String?
    let onRestoreBundledReading: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        original: Entry?,
        onSave: @escaping (_ key: String, _ reading: String, _ replacing: String?) -> String?,
        onRestoreBundledReading: @escaping () -> Void = {}
    ) {
        self.original = original
        self.onSave = onSave
        self.onRestoreBundledReading = onRestoreBundledReading
    }

    var body: some View {
        DictEntryEditSheet(
            originalKey: original?.key ?? "",
            originalValue: original?.reading ?? "",
            dictType: .vietPhrase, // chỉ nuôi badge mặc định — `badgeText` thay
            scopeBookId: nil,
            chipBookId: nil,
            existingValue: { key in QuickTranslationSurnameStore.shared.entries().first { $0.key == key }?.reading },
            onUpdate: { _, _ in },
            onAddEntry: { _, _ in },
            onDefinitionsChanged: {},
            badgeText: "Họ · Chung",
            listMode: DictEntryEditListMode(
                meaningPlaceholder: "Âm Hán-Việt của họ (Vương, Âu Dương…)",
                keyError: { key, replacing in QuickTranslationSurnameStore.shared.keyError(key, replacing: replacing) },
                meaningError: { reading in QuickTranslationSurnameStore.shared.readingError(reading) },
                save: { key, reading, replacing in onSave(key, reading, replacing) },
                extraRows: extraRows
            )
        )
    }

    private var extraRows: ((_ key: String, _ reading: String) -> AnyView)? {
        guard let row = restoreRow else { return nil }
        return { _, _ in row }
    }

    /// Họ gốc đã đổi âm ⇒ nút "Về âm gốc: Vương"; không thì không có hàng phụ.
    private var restoreRow: AnyView? {
        guard let original, original.isEdited, let bundled = original.bundledReading else { return nil }
        return AnyView(
            Button {
                onRestoreBundledReading()
                dismiss()
            } label: {
                Label("Về âm gốc: \(bundled)", systemImage: "arrow.uturn.backward")
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
    }
}
