import Foundation

/// Một mục hậu tố / tiền tố **kèm phạm vi** R (Riêng truyện) | C (Chung) — 2026-11-28, mockup
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2 / M3. Dùng chung cho hàng chip ở màn Sửa từ của màn duyệt
/// (`LocalNameFilterSuffixQuickRow`) và màn Quản lý tiền tố, hậu tố (`LocalNameFilterAffixManagerView`): chạm một mục ⇒ màn
/// Sửa từ mở đúng phạm vi của nó.
///
/// Đọc thẳng store (không cache — store đọc `UserDefaults` mỗi lần) ⇒ nơi dùng đọc lại sau mỗi lần ghi.
struct LocalNameFilterAffixScopedEntry: Identifiable, Equatable {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Scope = LocalNameFilterAffixListStore.Scope

    let entry: Entry
    let scope: Scope

    var id: String { "\(scope.rawValue):\(entry.key)" }
    var key: String { entry.key }

    /// Mục Riêng của truyện (mới thêm đứng đầu).
    static func book(flavor: LocalNameFilterAffixListFlavor, bookId: String) -> [Self] {
        guard !bookId.isEmpty else { return [] }
        return flavor.store.bookStore.entries(bookId: bookId).map { Self(entry: $0, scope: .book) }
    }

    /// Mục Chung (tự thêm đứng đầu, rồi mục gốc theo thứ tự file).
    static func common(flavor: LocalNameFilterAffixListFlavor) -> [Self] {
        flavor.store.entries().map { Self(entry: $0, scope: .common) }
    }

    /// Danh sách **hiệu lực** của truyện, cùng thứ tự và luật với `LocalNameFilterAffixListStore.effective(bookId:)`: mục
    /// Riêng rồi mục Chung không trùng chữ — mỗi chữ một mục, bản Riêng thắng. `bookId` rỗng ⇒ chỉ Chung.
    static func effective(flavor: LocalNameFilterAffixListFlavor, bookId: String) -> [Self] {
        let bookEntries = Self.book(flavor: flavor, bookId: bookId)
        let bookKeys = Set(bookEntries.map(\.key))
        return bookEntries + Self.common(flavor: flavor).filter { !bookKeys.contains($0.key) }
    }
}
