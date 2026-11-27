import Foundation

/// Chủ dữ liệu danh sách **"Không phải name"** của Lọc name local (dùng chung mọi truyện): các cụm chữ Hán người dùng
/// đánh dấu là rác. Bộ lọc **khớp nguyên cụm** và chỉ lọc ở đầu ra (`LocalNameFilter.Configuration.blockedTerms`):
/// chặn 唐三做 không làm 唐三 biến mất.
///
/// - Lưu ở `UserDefaults` khoá `localNameFilterBlockedTerms` = chuỗi JSON mảng `[{"term":"唐三做","addedAt":1795000000}]`
///   (`addedAt` = giây từ 1970). Khoá chữ thường ⇒ `BackupSettingsArchiver` tự gói. Danh sách rỗng ⇒ xoá khoá.
/// - Thêm từ màn duyệt (✕ › "Không phải name") hoặc nút + của màn quản lý; trần `maxCount` cụm.
/// - Đọc `UserDefaults` mỗi lần (không cache) nên bước khôi phục của Backup có hiệu lực ngay; mọi lời gọi đến từ main.
///
/// Ranh giới tầng: Service ⇒ không `import SwiftUI`, không `ToastManager`; lỗi trả chuỗi cho View tự báo.
final class LocalNameFilterBlocklistStore {
    struct Entry: Codable, Identifiable, Equatable, Sendable {
        let term: String
        let addedAt: Date

        var id: String { term }
    }

    static let shared = LocalNameFilterBlocklistStore()

    /// Chữ thường để `BackupSettingsArchiver` tự sao lưu.
    static let userDefaultsKey = "localNameFilterBlockedTerms"
    /// Trần hợp lý: mỗi lượt lọc chụp cả danh sách thành `Set`.
    static let maxCount = 5_000
    /// Ứng viên của bộ lọc ngắn; trần này chỉ chặn gõ / dán nhầm cả đoạn.
    static let maxTermLength = 20

    private init() {}

    // MARK: - Đọc

    /// Mới thêm đứng đầu.
    func entries() -> [Entry] {
        Self.load().sorted { lhs, rhs in
            lhs.addedAt != rhs.addedAt ? lhs.addedAt > rhs.addedAt : lhs.term < rhs.term
        }
    }

    /// Bộ cụm cho `LocalNameFilter.Configuration.blockedTerms` — màn "Lọc name local" chụp lúc bấm "Bắt đầu lọc".
    func terms() -> Set<String> {
        Set(Self.load().map(\.term))
    }

    /// Số cụm — giá trị hàng "Không phải name" ở sheet Lọc name local.
    var count: Int { Self.load().count }

    func contains(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.load().contains { $0.term == trimmed }
    }

    // MARK: - Kiểm tra

    /// Luật cụm (kể cả trùng) cho sheet thêm. `nil` = thêm được.
    func termError(_ rawTerm: String) -> String? {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = Self.formatError(term) { return error }
        if contains(term) { return "\(term) đã có trong danh sách." }
        return nil
    }

    // MARK: - Ghi

    /// Thêm một cụm (bỏ khoảng trắng hai đầu). Trả `nil` khi sau lệnh cụm **có** trong danh sách — vừa thêm, hoặc đã có
    /// từ trước (trùng ⇒ không thêm lần nữa, giữ ngày thêm cũ); trả chuỗi lỗi tiếng Việt khi **không** thêm được (không
    /// phải chữ Hán, quá dài, danh sách đầy, không ghi được). Gọi bỏ qua kết quả được: `store.add(term)`.
    @discardableResult
    func add(_ rawTerm: String) -> String? {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = Self.formatError(term) { return error }
        var entries = Self.load()
        if entries.contains(where: { $0.term == term }) { return nil }
        guard entries.count < Self.maxCount else {
            return "Danh sách “Không phải name” đã đủ \(Self.maxCount) cụm — xoá bớt rồi thêm lại."
        }
        entries.append(Entry(term: term, addedAt: Date()))
        return Self.save(entries)
    }

    /// Đổi một cụm thành cụm khác (màn Sửa từ của danh sách), giữ chỗ và ngày thêm cũ. Cụm cũ không còn ⇒ thêm như
    /// `add`. `nil` = đã đổi (hoặc không đổi gì); chuỗi = lỗi (sai luật, trùng cụm khác, không ghi được).
    @discardableResult
    func replace(_ oldTerm: String, with rawTerm: String) -> String? {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = Self.formatError(term) { return error }
        var entries = Self.load()
        guard let index = entries.firstIndex(where: { $0.term == oldTerm }) else { return add(term) }
        guard term != oldTerm else { return nil }
        if entries.contains(where: { $0.term == term }) { return "\(term) đã có trong danh sách." }
        entries[index] = Entry(term: term, addedAt: entries[index].addedAt)
        return Self.save(entries)
    }

    @discardableResult
    func remove(_ term: String) -> String? {
        let entries = Self.load()
        let remaining = entries.filter { $0.term != term }
        guard remaining.count != entries.count else { return nil }
        return Self.save(remaining)
    }

    /// "Xoá hết" của màn quản lý.
    func removeAll() {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
    }

    // MARK: - Nội bộ

    private static func formatError(_ term: String) -> String? {
        if term.isEmpty { return "Chưa nhập cụm chữ Hán." }
        guard LocalNameFilterSuffixListParser.isHanText(term) else { return "Chỉ nhập chữ Hán, không dấu cách." }
        if term.unicodeScalars.count > maxTermLength { return "Cụm dài quá \(maxTermLength) chữ." }
        return nil
    }

    private static let corruptLogLock = NSLock()
    private static var lastCorruptRaw: String?

    /// Khoá vắng ⇒ rỗng; JSON hỏng ⇒ rỗng + log (lần ghi sau ghi đè bản hỏng).
    private static func load() -> [Entry] {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey), let data = raw.data(using: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let entries = try? decoder.decode([Entry].self, from: data) else {
            // `load()` chạy cả trong `body` (kiểm từng phím gõ) ⇒ chỉ log **một lần** cho mỗi chuỗi hỏng.
            corruptLogLock.lock()
            let isNew = lastCorruptRaw != raw
            lastCorruptRaw = raw
            corruptLogLock.unlock()
            if isNew {
                AppLogger.shared.log("❌ [LọcName] Danh sách “Không phải name” hỏng, tạm coi là rỗng")
            }
            return []
        }
        return entries
    }

    /// Rỗng ⇒ xoá khoá. `nil` = đã ghi; chuỗi = lỗi.
    private static func save(_ entries: [Entry]) -> String? {
        if entries.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            return nil
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entries), let raw = String(data: data, encoding: .utf8) else {
            AppLogger.shared.log("❌ [LọcName] Không mã hoá được danh sách “Không phải name”")
            return "Không lưu được danh sách “Không phải name”."
        }
        UserDefaults.standard.set(raw, forKey: userDefaultsKey)
        return nil
    }
}
