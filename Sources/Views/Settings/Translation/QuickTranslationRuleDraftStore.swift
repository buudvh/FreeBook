import Foundation

/// Bản nháp của màn thêm/sửa rule, sống **ngoài** cây view.
///
/// Vì sao cần tới nó: `QuickTranslationRuleEditorSheet` giữ chữ đang gõ trong `@State` của chính nó,
/// mà `@State` chỉ sống theo *identity* của view. Khi Reader bên dưới tự chuyển chương lúc đang nghe,
/// SwiftUI dựng lại content của sheet (sheet vẫn mở), `init` chạy lại và mọi ô về giá trị seed — người
/// dùng mất sạch chữ gõ dở. Đường sửa "sách vở" là hoist state lên view chủ, nhưng `@State` không khai
/// được trong extension và `ReaderView.swift` đã vượt baseline dòng của `check_architecture.py` (chỉ
/// được giảm), nên chỗ duy nhất còn lại là một store bên ngoài.
///
/// Cố ý **không** `ObservableObject`: `@State` của sheet vẫn là nguồn sự thật cho `TextField`, store
/// chỉ là bản sao để `init` khôi phục. Phát `objectWillChange` mỗi keystroke chỉ thêm một lượt
/// invalidate vô ích.
///
/// Một slot duy nhất theo `Mode.id`: mở rule khác là draft cũ tự bị bỏ, nên không có gì rò rỉ. Draft
/// **không** bị xoá ở `onDisappear` — nếu lượt dựng lại có kèm một lần disappear thì chính nó sẽ ăn mất
/// bản nháp, đúng thứ đang phải chữa. Xoá chỉ ở hai hành động dứt khoát của người dùng: lưu thành công
/// và bấm Hủy. Hệ quả có chủ ý: vuốt xuống đóng sheet rồi mở lại **cùng** rule thì chữ còn nguyên.
final class QuickTranslationRuleDraftStore {
    static let shared = QuickTranslationRuleDraftStore()

    enum Field: Hashable {
        case pattern
        case replacement
    }

    struct Draft: Equatable {
        var pattern: String
        var replacement: String
        var saveToBook: Bool
        /// Vùng chọn trong mẫu, tính theo **chỉ số ký tự** của `Array(pattern)`.
        var selectionStart: Int
        var selectionLength: Int
        /// Vùng chọn trong ô Bản dịch, cùng đơn vị. Có từ 1.3.336, khi ô đó cũng có con trỏ thật để
        /// chip `{i}` chèn đúng chỗ — không lưu thì mỗi lượt dựng lại sheet con trỏ nhảy về cuối.
        var replacementSelectionStart: Int
        var replacementSelectionLength: Int
        var focus: Field?
    }

    private let lock = NSLock()
    private nonisolated(unsafe) var currentID: String?
    private nonisolated(unsafe) var currentDraft: Draft?

    private init() {}

    func draft(for id: String) -> Draft? {
        lock.lock()
        defer { lock.unlock() }
        guard currentID == id else { return nil }
        return currentDraft
    }

    func store(_ draft: Draft, for id: String) {
        lock.lock()
        currentID = id
        currentDraft = draft
        lock.unlock()
    }

    func clear(id: String) {
        lock.lock()
        if currentID == id {
            currentID = nil
            currentDraft = nil
        }
        lock.unlock()
    }
}
