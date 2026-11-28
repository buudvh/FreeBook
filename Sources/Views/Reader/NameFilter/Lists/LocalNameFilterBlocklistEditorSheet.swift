import SwiftUI

/// Sheet **thêm / sửa một cụm** của danh sách "Không phải name" = màn **Sửa từ** của từ điển (`DictEntryEditSheet` chế độ
/// danh sách, plan 2026-11-27 — anh Bửu: danh sách vế trái chữ Hán làm kiểu Sửa từ) nhưng **chỉ** hàng chữ gốc chọn được +
/// hàng token: không ô nghĩa, chip, aa…AA. Mở từ nút `+` (khoá rỗng ⇒ "Thêm từ", ô gõ chữ gốc mở sẵn) hoặc chạm thân hàng
/// của `LocalNameFilterBlocklistView`. Chỗ trình bày bọc `Group { … }.appGlassSheet()`.
///
/// - Phạm vi theo chip đang chọn của màn danh sách (2026-11-28, mockup N4 — không có cụm R | C): badge "Không phải name ·
///   Chung" / "Không phải name · Riêng truyện"; luật + trùng lấy từ store của phạm vi đó
///   (`LocalNameFilterBlocklistStore.termError` / `LocalNameFilterBookBlocklistStore.termError`, cụm giữ nguyên khi sửa
///   không tính là trùng), hiện đỏ ở dòng thông báo; ô trống không tô đỏ.
/// - Chọn cả cụm (kể cả gõ lại bằng bút chì) ⇒ đổi cụm (`replacing` = cụm cũ); chọn một phần ⇒ thêm cụm mới = phần đang
///   chọn, cụm đang sửa giữ nguyên (`replacing == nil`).
/// - Ghi do màn danh sách làm (`onSave` trả chuỗi lỗi nếu không lưu được — sheet giữ nguyên để sửa tiếp).
struct LocalNameFilterBlocklistEditorSheet: View {
    typealias Store = LocalNameFilterBlocklistStore
    typealias BookStore = LocalNameFilterBookBlocklistStore

    /// `nil` = thêm cụm mới.
    let original: String?
    /// Danh sách đích; `.book` cần `bookId`.
    let scope: LocalNameFilter.BlockScope
    let bookId: String?
    let onSave: (_ term: String, _ replacing: String?) -> String?

    init(
        original: String?,
        scope: LocalNameFilter.BlockScope = .common,
        bookId: String? = nil,
        onSave: @escaping (_ term: String, _ replacing: String?) -> String?
    ) {
        self.original = original
        self.scope = scope
        self.bookId = bookId
        self.onSave = onSave
    }

    private var isBookScope: Bool { scope == .book && bookId?.isEmpty == false }

    var body: some View {
        DictEntryEditSheet(
            originalKey: original ?? "",
            originalValue: "",
            dictType: .vietPhrase, // chỉ nuôi badge mặc định — `badgeText` thay
            scopeBookId: nil,
            chipBookId: nil,
            existingValue: { _ in nil },
            onUpdate: { _, _ in },
            onAddEntry: { _, _ in },
            onDefinitionsChanged: {},
            badgeText: isBookScope ? "Không phải name · Riêng truyện" : "Không phải name · Chung",
            listMode: DictEntryEditListMode(
                showsMeaning: false,
                keyError: { term, replacing in
                    // Cụm đang sửa giữ nguyên thì đã nằm trong danh sách — `termError` sẽ báo trùng nhầm.
                    guard term != replacing else { return nil }
                    if isBookScope, let bookId { return BookStore.shared.termError(term, bookId: bookId) }
                    return Store.shared.termError(term)
                },
                save: { term, _, replacing in onSave(term, replacing) }
            )
        )
    }
}
