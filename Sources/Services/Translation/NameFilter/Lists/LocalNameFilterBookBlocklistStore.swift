import Foundation

/// Danh sách **"Không phải name" riêng truyện** của Lọc name local (2026-11-28, mockup
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung N1 / N4, plan "Plan đợt bổ sung") — lớp thứ hai bên cạnh danh
/// sách Chung (`LocalNameFilterBlocklistStore`): cụm chỉ là rác ở **một** truyện (猎魔子弹 của truyện này có thể là tên thật
/// ở truyện khác). Bộ lọc của một truyện chặn theo **Chung + Riêng** (`effectiveTerms(bookId:)`), cùng luật khớp nguyên cụm,
/// chỉ ở đầu ra; gói tạm tự bỏ name bị chặn ở cả hai.
///
/// - **Lưu**: `UserDefaults` khoá `localNameFilterBookBlockedTerms` = chuỗi JSON `{bookId: [{"term":…,"addedAt":…}]}`
///   (`addedAt` = giây từ 1970, cùng kiểu mục với danh sách Chung); chỉ giữ truyện có cụm (hết cụm ⇒ bỏ truyện, hết truyện ⇒
///   xoá khoá). Khoá chữ thường không dấu chấm ⇒ `BackupSettingsArchiver` tự gói.
/// - **Luật**: cụm như danh sách Chung (`LocalNameFilterBlocklistStore.formatError`); trần `maxCount` cụm mỗi truyện; trùng
///   **trong cùng truyện** ⇒ không thêm lần nữa. Cùng cụm với danh sách Chung thì được (hai danh sách độc lập — xoá khỏi Chung
///   thì truyện này vẫn chặn).
/// - **Đổi nguồn** (`BookSourceMigrator.copyBookScopedSettings`): `copy(from:to:)` gộp theo cụm, giữ ngày thêm của truyện cũ.
///   **Xoá**: `remove(bookId:)` ở `removeBookScopedSettings` và `BookStorageManager.deleteBookSideData`.
/// - Không cache, đọc `UserDefaults` mỗi lần (khôi phục Backup có hiệu lực ngay); đọc – sửa – ghi tuần tự bằng khoá (đổi
///   nguồn chạy ngoài main).
///
/// Ranh giới tầng: Service ⇒ không `import SwiftUI`, không `ToastManager`; lỗi trả chuỗi cho View tự báo.
final class LocalNameFilterBookBlocklistStore: @unchecked Sendable {
    typealias Entry = LocalNameFilterBlocklistStore.Entry

    static let shared = LocalNameFilterBookBlocklistStore()

    /// Chữ thường, không dấu chấm để `BackupSettingsArchiver` tự sao lưu.
    static let userDefaultsKey = "localNameFilterBookBlockedTerms"
    /// Trần mỗi truyện — như danh sách Chung.
    static let maxCount = LocalNameFilterBlocklistStore.maxCount

    /// Khoá đọc – sửa – ghi (không `private` để file `+Import` trộn rồi ghi một lần dưới cùng khoá).
    let lock = NSLock()
    private let corruptLogLock = NSLock()
    private var lastCorruptRaw: String?

    private init() {}

    /// Bộ cụm bộ lọc của truyện chặn = Chung + Riêng truyện (`LocalNameFilter.Configuration.blockedTerms`, gói tạm tự cập
    /// nhật). `bookId` rỗng ⇒ chỉ Chung.
    static func effectiveTerms(bookId: String) -> Set<String> {
        LocalNameFilterBlocklistStore.shared.terms().union(shared.terms(bookId: bookId))
    }

    // MARK: - Đọc

    /// Cụm riêng của truyện, mới thêm đứng đầu. `bookId` rỗng ⇒ rỗng.
    func entries(bookId: String) -> [Entry] {
        items(bookId: bookId).sorted { lhs, rhs in
            lhs.addedAt != rhs.addedAt ? lhs.addedAt > rhs.addedAt : lhs.term < rhs.term
        }
    }

    func terms(bookId: String) -> Set<String> {
        Set(items(bookId: bookId).map(\.term))
    }

    func count(bookId: String) -> Int {
        items(bookId: bookId).count
    }

    func contains(_ term: String, bookId: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        return items(bookId: bookId).contains { $0.term == trimmed }
    }

    // MARK: - Kiểm tra

    /// Luật cụm + trùng trong truyện cho màn Sửa từ. `nil` = thêm được.
    func termError(_ rawTerm: String, bookId: String) -> String? {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = LocalNameFilterBlocklistStore.formatError(term) { return error }
        if bookId.isEmpty { return Self.noBookError }
        if contains(term, bookId: bookId) { return "\(term) đã có trong danh sách riêng của truyện." }
        return nil
    }

    // MARK: - Ghi

    /// Thêm một cụm (bỏ khoảng trắng hai đầu). Như `LocalNameFilterBlocklistStore.add`: `nil` khi sau lệnh cụm **có** trong
    /// danh sách riêng (vừa thêm, hoặc đã có — giữ ngày thêm cũ); chuỗi lỗi khi không thêm được.
    @discardableResult
    func add(_ rawTerm: String, bookId: String) -> String? {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = LocalNameFilterBlocklistStore.formatError(term) { return error }
        if bookId.isEmpty { return Self.noBookError }
        lock.lock()
        defer { lock.unlock() }
        var table = currentTable()
        var list = table[bookId] ?? []
        if list.contains(where: { $0.term == term }) { return nil }
        guard list.count < Self.maxCount else {
            return "Danh sách “Không phải name” riêng của truyện đã đủ \(Self.maxCount) cụm — xoá bớt rồi thêm lại."
        }
        list.append(Entry(term: term, addedAt: Date()))
        table[bookId] = list
        return write(table)
    }

    /// Đổi một cụm riêng thành cụm khác (màn Sửa từ), giữ chỗ và ngày thêm cũ. Cụm cũ không còn ⇒ thêm như `add`. `nil` = đã
    /// đổi (hoặc không đổi gì); chuỗi = lỗi.
    @discardableResult
    func replace(_ oldTerm: String, with rawTerm: String, bookId: String) -> String? {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = LocalNameFilterBlocklistStore.formatError(term) { return error }
        if bookId.isEmpty { return Self.noBookError }
        lock.lock()
        var table = currentTable()
        var list = table[bookId] ?? []
        guard let index = list.firstIndex(where: { $0.term == oldTerm }) else {
            lock.unlock()
            return add(term, bookId: bookId)
        }
        defer { lock.unlock() }
        guard term != oldTerm else { return nil }
        if list.contains(where: { $0.term == term }) { return "\(term) đã có trong danh sách riêng của truyện." }
        list[index] = Entry(term: term, addedAt: list[index].addedAt)
        table[bookId] = list
        return write(table)
    }

    /// Bỏ một cụm riêng (không có ⇒ không làm gì).
    @discardableResult
    func remove(_ term: String, bookId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        var table = currentTable()
        guard let list = table[bookId], list.contains(where: { $0.term == term }) else { return nil }
        let kept = list.filter { $0.term != term }
        table[bookId] = kept.isEmpty ? nil : kept
        return write(table)
    }

    /// Xoá cả danh sách riêng của một truyện ("Xoá hết" ở chip Riêng truyện, xoá truyện, bản cũ sau mốc chốt đổi nguồn).
    func remove(bookId: String) {
        guard !bookId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var table = currentTable()
        guard table[bookId] != nil else { return }
        table[bookId] = nil
        write(table)
    }

    /// Đổi nguồn: gộp cụm riêng của truyện cũ vào truyện đích — cụm trùng giữ ngày thêm của truyện cũ, cụm chỉ truyện đích có
    /// giữ nguyên. Không xoá gì; chạy lại nhiều lần cho cùng kết quả.
    func copy(from oldBookId: String, to newBookId: String) {
        guard !oldBookId.isEmpty, !newBookId.isEmpty, oldBookId != newBookId else { return }
        lock.lock()
        defer { lock.unlock() }
        var table = currentTable()
        guard let old = table[oldBookId], !old.isEmpty else { return }
        let oldTerms = Set(old.map(\.term))
        let merged = old + (table[newBookId] ?? []).filter { !oldTerms.contains($0.term) }
        guard merged != table[newBookId] else { return }
        table[newBookId] = merged
        write(table)
    }

    // MARK: - Nội bộ

    static let noBookError = "Không có truyện để lưu cụm riêng."

    private func items(bookId: String) -> [Entry] {
        guard !bookId.isEmpty else { return [] }
        return currentTable()[bookId] ?? []
    }

    /// Khoá vắng hoặc JSON hỏng ⇒ rỗng (log ❌ một lần cho mỗi chuỗi hỏng).
    func currentTable() -> [String: [Entry]] {
        guard let raw = UserDefaults.standard.string(forKey: Self.userDefaultsKey), let data = raw.data(using: .utf8) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let decoded = try? decoder.decode([String: [Entry]].self, from: data) else {
            corruptLogLock.lock()
            let isNew = lastCorruptRaw != raw
            lastCorruptRaw = raw
            corruptLogLock.unlock()
            if isNew {
                AppLogger.shared.log("❌ [LọcName] Danh sách “Không phải name” riêng truyện hỏng, tạm coi là rỗng")
            }
            return [:]
        }
        return decoded
    }

    /// Gọi khi đang giữ `lock`. Bảng rỗng ⇒ xoá khoá. `nil` = đã ghi; chuỗi = lỗi.
    @discardableResult
    func write(_ table: [String: [Entry]]) -> String? {
        let cleaned = table.filter { !$0.key.isEmpty && !$0.value.isEmpty }
        if cleaned.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
            return nil
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(cleaned), let raw = String(data: data, encoding: .utf8) else {
            AppLogger.shared.log("❌ [LọcName] Không mã hoá được danh sách “Không phải name” riêng truyện")
            return "Không lưu được danh sách “Không phải name” riêng."
        }
        UserDefaults.standard.set(raw, forKey: Self.userDefaultsKey)
        return nil
    }
}
