import Foundation

/// Danh sách **"Hậu tố" / "Tiền tố" riêng truyện** của Lọc name local (2026-11-28, plan "Tiền tố hậu tố riêng truyện" mục
/// B4–B5, mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M3 / M5 / M6) — lớp thứ hai bên cạnh danh sách
/// Chung (`LocalNameFilterSuffixStore` / `LocalNameFilterPrefixStore`, cùng dạng mục `chữ Hán=nghĩa|loại|vị trí`).
///
/// - **Lưu**: `UserDefaults` khoá `localNameFilterBookSuffixes` / `localNameFilterBookPrefixes` = chuỗi JSON
///   `{bookId: [{key, meaning, kind, position}]}`; chỉ giữ truyện có mục (hết mục ⇒ bỏ truyện, hết truyện ⇒ xoá khoá). Khoá
///   chữ thường không dấu chấm ⇒ `BackupSettingsArchiver` tự gói.
/// - **Thứ tự**: mục mới thêm đứng đầu; sửa (kể cả đổi chữ) giữ chỗ.
/// - **Luật**: khoá + nghĩa như danh sách Chung (`LocalNameFilterSuffixListParser`); trùng khoá **trong cùng truyện** ⇒ lỗi.
///   Cùng chữ với một mục Chung thì được — ở danh sách hiệu lực bản Riêng thắng (`LocalNameFilterAffixListStore.effective`).
/// - **Đổi nguồn** (`BookSourceMigrator.copyBookScopedSettings`): `copy(from:to:)` gộp theo khoá, mục truyện cũ thắng (như
///   từ điển riêng 1.3.946 — "đích đã có thì giữ" từng làm mất mục). **Xoá**: `remove(bookId:)` ở
///   `removeBookScopedSettings` và `BookStorageManager.deleteBookSideData`.
/// - Không cache, đọc `UserDefaults` mỗi lần (khôi phục Backup có hiệu lực ngay); đọc – sửa – ghi tuần tự bằng khoá (đổi
///   nguồn chạy ngoài main). Không đi vào bộ dịch ⇒ ghi không dọn cache dịch, không báo rule đổi.
///
/// Ranh giới tầng: Service ⇒ không `import SwiftUI`, không `ToastManager`; lỗi trả chuỗi cho View tự báo.
final class LocalNameFilterBookAffixStore: @unchecked Sendable {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Parser = LocalNameFilterSuffixListParser

    static let suffixes = LocalNameFilterBookAffixStore(defaultsKey: "localNameFilterBookSuffixes", noun: "Hậu tố")
    static let prefixes = LocalNameFilterBookAffixStore(defaultsKey: "localNameFilterBookPrefixes", noun: "Tiền tố")

    /// Một mục trong JSON (không `private` để file `+Import` dựng mục từ dòng file).
    struct StoredItem: Codable, Equatable {
        let key: String
        let meaning: String
        let kind: LocalNameFilter.SuffixKind
        let position: LocalNameFilter.MeaningPosition
    }

    /// Khoá `UserDefaults` (chữ thường đầu, không dấu chấm để Backup tự gói).
    let defaultsKey: String
    /// Danh từ của một mục trong lỗi: "Hậu tố", "Tiền tố".
    let noun: String

    /// Khoá đọc – sửa – ghi (không `private` để file `+Import` trộn rồi ghi một lần dưới cùng khoá).
    let lock = NSLock()
    private let corruptLogLock = NSLock()
    private var lastCorruptRaw: String?

    private init(defaultsKey: String, noun: String) {
        self.defaultsKey = defaultsKey
        self.noun = noun
    }

    // MARK: - Đọc

    /// Mục riêng của truyện, mới thêm đứng đầu — cùng kiểu với danh sách Chung để màn danh sách vẽ chung hàng (`origin`
    /// luôn `.userAdded`, không có bản gốc). `bookId` rỗng ⇒ rỗng.
    func entries(bookId: String) -> [Entry] {
        items(bookId: bookId).map { item in
            Entry(key: item.key, value: Entry.Value(meaning: item.meaning, kind: item.kind, position: item.position),
                  origin: .userAdded, bundledValue: nil)
        }
    }

    /// Mục riêng của truyện đúng dạng bộ lọc dùng.
    func affixes(bookId: String) -> [LocalNameFilter.Suffix] {
        items(bookId: bookId).map {
            LocalNameFilter.Suffix(key: $0.key, meaning: $0.meaning, kind: $0.kind, position: $0.position)
        }
    }

    func count(bookId: String) -> Int {
        items(bookId: bookId).count
    }

    /// Truyện có mục riêng chữ `key` (mục Chung cùng chữ bị che ở danh sách hiệu lực).
    func contains(bookId: String, key: String) -> Bool {
        items(bookId: bookId).contains { $0.key == key }
    }

    // MARK: - Kiểm tra

    /// Luật khoá + trùng khoá trong truyện. `originalKey` = khoá riêng đang sửa của **chính truyện này** (giữ nguyên chữ
    /// không tính là trùng); thêm mới hoặc chuyển từ Chung sang ⇒ `nil`.
    func keyError(_ key: String, bookId: String, replacing originalKey: String?) -> String? {
        if let error = Parser.keyError(key, noun: noun) { return error }
        if bookId.isEmpty { return "Không có truyện để lưu \(noun.lowercased()) riêng." }
        if key != originalKey, contains(bookId: bookId, key: key) {
            return "\(noun) \(key) đã có trong danh sách riêng của truyện."
        }
        return nil
    }

    func meaningError(_ meaning: String) -> String? {
        Parser.meaningError(meaning)
    }

    // MARK: - Ghi

    /// Thêm (`originalKey == nil` hoặc không còn) hoặc sửa một mục riêng. Đổi chữ Hán = thay mục cũ tại chỗ. `nil` = đã
    /// lưu; chuỗi = lỗi (không ghi gì).
    @discardableResult
    func save(bookId: String, key rawKey: String, meaning rawMeaning: String, kind: LocalNameFilter.SuffixKind,
              position: LocalNameFilter.MeaningPosition, replacing originalKey: String?) -> String? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = rawMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        if let error = keyError(key, bookId: bookId, replacing: originalKey) ?? meaningError(meaning) { return error }
        var table = currentTable()
        var list = table[bookId] ?? []
        let item = StoredItem(key: key, meaning: meaning, kind: kind, position: position)
        if let originalKey, let index = list.firstIndex(where: { $0.key == originalKey }) {
            list[index] = item
        } else {
            list.insert(item, at: 0)
        }
        table[bookId] = list
        return write(table)
    }

    /// Bỏ mục riêng chữ `key` (không có ⇒ không làm gì). `nil` = xong; chuỗi = lỗi.
    @discardableResult
    func delete(bookId: String, key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        var table = currentTable()
        guard let list = table[bookId], list.contains(where: { $0.key == key }) else { return nil }
        let kept = list.filter { $0.key != key }
        table[bookId] = kept.isEmpty ? nil : kept
        return write(table)
    }

    /// Xoá cả danh sách riêng của một truyện (xoá truyện, bản cũ sau mốc chốt đổi nguồn).
    func remove(bookId: String) {
        guard !bookId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var table = currentTable()
        guard table[bookId] != nil else { return }
        table[bookId] = nil
        write(table)
    }

    /// Đổi nguồn: gộp danh sách riêng của truyện cũ vào truyện đích theo khoá — mục truyện cũ thắng và đứng trước, mục chỉ
    /// truyện đích có giữ nguyên. Không xoá gì; chạy lại nhiều lần cho cùng kết quả.
    func copy(from oldBookId: String, to newBookId: String) {
        guard !oldBookId.isEmpty, !newBookId.isEmpty, oldBookId != newBookId else { return }
        lock.lock()
        defer { lock.unlock() }
        var table = currentTable()
        guard let old = table[oldBookId], !old.isEmpty else { return }
        let oldKeys = Set(old.map(\.key))
        let merged = old + (table[newBookId] ?? []).filter { !oldKeys.contains($0.key) }
        guard merged != table[newBookId] else { return }
        table[newBookId] = merged
        write(table)
    }

    // MARK: - Nội bộ

    private func items(bookId: String) -> [StoredItem] {
        guard !bookId.isEmpty else { return [] }
        return currentTable()[bookId] ?? []
    }

    /// Khoá vắng hoặc JSON hỏng ⇒ rỗng (log ❌ một lần cho mỗi chuỗi hỏng).
    func currentTable() -> [String: [StoredItem]] {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey), let data = raw.data(using: .utf8) else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: [StoredItem]].self, from: data) else {
            corruptLogLock.lock()
            let isNew = lastCorruptRaw != raw
            lastCorruptRaw = raw
            corruptLogLock.unlock()
            if isNew {
                AppLogger.shared.log("❌ [LọcName] Danh sách \(noun.lowercased()) riêng truyện hỏng, tạm coi như rỗng")
            }
            return [:]
        }
        return decoded
    }

    /// Gọi khi đang giữ `lock`. Bảng rỗng ⇒ xoá khoá. `nil` = đã ghi; chuỗi = lỗi.
    @discardableResult
    func write(_ table: [String: [StoredItem]]) -> String? {
        let cleaned = table.filter { !$0.key.isEmpty && !$0.value.isEmpty }
        if cleaned.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(cleaned), let raw = String(data: data, encoding: .utf8) else {
            AppLogger.shared.log("❌ [LọcName] Không mã hoá được danh sách \(noun.lowercased()) riêng truyện")
            return "Không lưu được danh sách \(noun.lowercased()) riêng."
        }
        UserDefaults.standard.set(raw, forKey: defaultsKey)
        return nil
    }
}
