import Foundation

/// Công tắc **theo truyện** của Lọc name local, mặc định tắt — hai thể hiện cùng một khuôn:
/// - `shared` = **"Ưu tiên tên Latin"** (plan `Docs/Plans/2026-11-27-nghia-ten-tay-huyen.md` mục 3): bật cho truyện tây
///   huyễn (班森 ⇒ Benson, tên lạ máy đoán), để tắt cho truyện Trung (bật nhầm thì 史莱克 ⇒ Shrek). Khoá
///   `localNameFilterLatinByBook`.
/// - `loose` = **"Nới đoán tên Latin"** (2026-11-28, mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung N5): mô
///   hình đoán lõi của tên kiểu Latin khi ≥ một nửa số chữ là chữ phiên âm. Chỉ có tác dụng khi "Ưu tiên tên Latin" bật —
///   giá trị hiệu lực là `loosensLatin(bookId:)`. Khoá `localNameFilterLooseLatinByBook`.
///
/// `UserDefaults` = từ điển `bookId → Bool`, chỉ ghi truyện đã chạm công tắc (vắng = tắt). Khoá chữ thường không dấu chấm ⇒
/// `BackupSettingsArchiver` tự gói. Đổi nguồn chép theo (`BookSourceMigrator.copyBookScopedSettings`: truyện đích đã có giá
/// trị riêng thì giữ của đích), xoá truyện thì xoá (`removeBookScopedSettings`, `BookStorageManager.deleteBookSideData`).
final class LocalNameFilterLatinPreferenceStore: @unchecked Sendable {
    static let shared = LocalNameFilterLatinPreferenceStore(userDefaultsKey: "localNameFilterLatinByBook")
    static let loose = LocalNameFilterLatinPreferenceStore(userDefaultsKey: "localNameFilterLooseLatinByBook")

    let userDefaultsKey: String

    /// Đọc-sửa-ghi một từ điển `UserDefaults` chung cho mọi truyện ⇒ tuần tự hoá (đổi nguồn chạy ngoài main).
    private let lock = NSLock()

    private init(userDefaultsKey: String) {
        self.userDefaultsKey = userDefaultsKey
    }

    /// "Nới đoán tên Latin" **hiệu lực** của truyện = bật "Ưu tiên tên Latin" **và** bật "Nới" — giá trị truyền vào
    /// `LocalNameFilter.Configuration.loosensLatinGuess`, bộ ghép nghĩa và dấu gói tạm (mọi chỗ cùng một cách tính).
    static func loosensLatin(bookId: String) -> Bool {
        shared.isOn(bookId: bookId) && loose.isOn(bookId: bookId)
    }

    func isOn(bookId: String) -> Bool {
        guard !bookId.isEmpty else { return false }
        return (UserDefaults.standard.dictionary(forKey: userDefaultsKey)?[bookId] as? Bool) ?? false
    }

    func setOn(_ value: Bool, bookId: String) {
        guard !bookId.isEmpty else { return }
        update { $0[bookId] = value }
    }

    /// = `isOn` của `shared` (tên cũ, giữ cho các chỗ gọi "Ưu tiên tên Latin").
    func prefersLatin(bookId: String) -> Bool {
        isOn(bookId: bookId)
    }

    /// = `setOn` (tên cũ).
    func setPrefersLatin(_ value: Bool, bookId: String) {
        setOn(value, bookId: bookId)
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
        var table = UserDefaults.standard.dictionary(forKey: userDefaultsKey) ?? [:]
        let before = table.count
        change(&table)
        if table.isEmpty {
            if before > 0 { UserDefaults.standard.removeObject(forKey: userDefaultsKey) }
            return
        }
        UserDefaults.standard.set(table, forKey: userDefaultsKey)
    }
}
