import Foundation

/// Công tắc **"Ưu tiên tên Latin"** của Lọc name local, nhớ **theo truyện**, mặc định tắt (plan
/// `Docs/Plans/2026-11-27-nghia-ten-tay-huyen.md` mục 3): bật cho truyện tây huyễn (班森 ⇒ Benson, tên lạ máy đoán), để tắt
/// cho truyện Trung (bật nhầm thì 史莱克 ⇒ Shrek).
///
/// `UserDefaults` khoá `localNameFilterLatinByBook` = từ điển `bookId → Bool`, chỉ ghi truyện đã chạm công tắc (vắng = tắt).
/// Khoá chữ thường ⇒ `BackupSettingsArchiver` tự gói. Đổi nguồn chép theo (`BookSourceMigrator.copyBookScopedSettings`:
/// truyện đích đã có giá trị riêng thì giữ của đích), xoá truyện thì xoá (`removeBookScopedSettings`,
/// `BookStorageManager.deleteBookSideData`).
final class LocalNameFilterLatinPreferenceStore: @unchecked Sendable {
    static let shared = LocalNameFilterLatinPreferenceStore()

    static let userDefaultsKey = "localNameFilterLatinByBook"

    /// Đọc-sửa-ghi một từ điển `UserDefaults` chung cho mọi truyện ⇒ tuần tự hoá (đổi nguồn chạy ngoài main).
    private let lock = NSLock()

    private init() {}

    func prefersLatin(bookId: String) -> Bool {
        guard !bookId.isEmpty else { return false }
        return (UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey)?[bookId] as? Bool) ?? false
    }

    func setPrefersLatin(_ value: Bool, bookId: String) {
        guard !bookId.isEmpty else { return }
        update { $0[bookId] = value }
    }

    /// Chép giá trị của truyện cũ sang truyện đích nếu đích chưa có giá trị riêng. Không xoá gì.
    func copy(from oldBookId: String, to newBookId: String) {
        guard !oldBookId.isEmpty, !newBookId.isEmpty, oldBookId != newBookId else { return }
        update { table in
            guard table[newBookId] == nil, let value = table[oldBookId] as? Bool else { return }
            table[newBookId] = value
        }
    }

    func remove(bookId: String) {
        guard !bookId.isEmpty else { return }
        update { $0[bookId] = nil }
    }

    private func update(_ change: (inout [String: Any]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var table = UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey) ?? [:]
        let before = table.count
        change(&table)
        if table.isEmpty {
            if before > 0 { UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey) }
            return
        }
        UserDefaults.standard.set(table, forKey: Self.userDefaultsKey)
    }
}
