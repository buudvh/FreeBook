import Foundation

/// Chủ dữ liệu **token tùy chọn** `<@tên>` của rule dịch nhanh (1.3.1063).
///
/// - Lưu: `UserDefaults` khoá `quickTranslateCustomTokens` = JSON `{"tokens":[…]}` (`QuickTranslationCustomToken`). Khoá
///   chữ thường ⇒ `BackupSettingsArchiver` tự gói; không có thư mục dữ liệu mới. Rỗng ⇒ xoá khoá.
/// - Trần: 50 token, tổng 20.000 từ — vượt thì báo lỗi, không ghi (một chuỗi `UserDefaults` vài trăm KB là mức chấp nhận
///   được, hơn nữa thì nên đổi sang file).
/// - Đọc: `lookupTables()` chạy mỗi lượt rewrite (`QuickTranslationDictionaryToken.resolve`) từ nhiều luồng ⇒ cache bản
///   đã giải mã + bảng tra. Cache chỉ đem so với chuỗi thô sau khi `UserDefaults` báo **có** thay đổi
///   (`didChangeNotification`) — bước khôi phục Backup ghi thẳng `UserDefaults`, không qua store, mà so chuỗi vài trăm KB ở
///   mọi lượt rewrite thì phí.
/// - Mọi lần ghi dọn cache dịch + phát một tín hiệu rule đổi ⇒ có hiệu lực từ lượt dịch kế tiếp; bộ rule **không** phải
///   nạp lại vì parser không tra token lúc dịch rule (xem `QuickTranslationRuleParser+CustomToken`).
///
/// Ranh giới tầng: Service ⇒ không `import SwiftUI`, không `ToastManager`; lỗi trả chuỗi / ném cho View tự báo.
public final class QuickTranslationCustomTokenStore {
    public typealias Token = QuickTranslationCustomToken
    public typealias Entry = QuickTranslationCustomToken.Entry
    typealias Parser = QuickTranslationCustomTokenListParser

    public static let shared = QuickTranslationCustomTokenStore()

    /// Chữ thường để `BackupSettingsArchiver` tự sao lưu.
    public static let userDefaultsKey = "quickTranslateCustomTokens"
    public static let maxTokenCount = 50
    public static let maxTotalEntries = 20_000

    /// Bảng tra của một token **đang bật** và có từ: khoá → nghĩa, kèm độ dài khoá lớn nhất để vòng thử dài → ngắn
    /// bắt đầu đúng chỗ.
    public struct Table: Sendable {
        public let meanings: [String: String]
        public let maxKeyLength: Int
    }

    /// Tình trạng của một tên token mà rule gọi — nguồn của `DICT_TOKEN_WITHOUT_DICTIONARY` cho `<@tên>`.
    public enum Availability: Sendable {
        case usable
        case missing
        case disabled
        case empty
    }

    public struct ImportOutcome: Sendable {
        public let added: Int
        public let updated: Int
        /// Chỉ "Thay thế toàn bộ": số từ đang có mà file không có.
        public let removed: Int
        public let skipped: Int
    }

    public enum ImportError: LocalizedError {
        case unreadable
        case noValidLine(skipped: Int)
        case tooManyEntries
        case tokenMissing

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                return "Không đọc được file (cần file chữ UTF-8)."
            case .noValidLine(let skipped):
                return skipped > 0
                    ? "File không có dòng hợp lệ (bỏ qua \(skipped) dòng sai)."
                    : "File không có dòng nào."
            case .tooManyEntries:
                return "Vượt \(QuickTranslationCustomTokenStore.maxTotalEntries) từ cho mọi token tùy chọn."
            case .tokenMissing:
                return "Token không còn."
            }
        }
    }

    private struct Payload: Codable {
        var tokens: [Token] = []
    }

    private struct Cache {
        let raw: String?
        let tokens: [Token]
        let tables: [String: Table]
    }

    private let lock = NSLock()
    private nonisolated(unsafe) var cache: Cache?
    private nonisolated(unsafe) var isDirty = true
    private nonisolated(unsafe) var defaultsObserver: NSObjectProtocol?

    private init() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.markDirty()
        }
    }

    // MARK: - Đọc

    /// Mọi token theo thứ tự tạo (kể cả đang tắt).
    public func tokens() -> [Token] { currentCache().tokens }

    public func token(named name: String) -> Token? {
        tokens().first { $0.name == name }
    }

    /// "2 token · 1 đang tắt" của hàng Token tùy chọn.
    public func summary() -> (total: Int, disabled: Int) {
        let all = tokens()
        return (all.count, all.filter { !$0.isEnabled }.count)
    }

    /// Bảng tra của engine: tên → bảng, chỉ token **đang bật** và có từ.
    public func lookupTables() -> [String: Table] { currentCache().tables }

    public func availability(of name: String) -> Availability {
        guard let token = token(named: name) else { return .missing }
        if !token.isEnabled { return .disabled }
        return token.entries.isEmpty ? .empty : .usable
    }

    // MARK: - Kiểm tra (dùng chung sheet và lúc lưu)

    /// Luật tên + trùng tên. `nil` = hợp lệ.
    public func nameError(_ name: String) -> String? {
        if let error = Parser.nameError(name) { return error }
        return token(named: name) == nil ? nil : "Đã có token <@\(name)>."
    }

    /// Luật chữ gốc + trùng chữ trong cùng token. `originalKey` = chữ đang sửa (giữ nguyên không tính là trùng).
    public func keyError(_ key: String, in tokenName: String, replacing originalKey: String?) -> String? {
        if let error = Parser.keyError(key) { return error }
        guard key != originalKey, token(named: tokenName)?.entries.contains(where: { $0.key == key }) == true else {
            return nil
        }
        return "Chữ \(key) đã có trong <@\(tokenName)>."
    }

    public func meaningError(_ meaning: String) -> String? {
        Parser.meaningError(meaning)
    }

    // MARK: - Ghi token (`nil` = đã lưu; chuỗi = lỗi)

    @discardableResult
    public func createToken(name rawName: String, title rawTitle: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = nameError(name) { return error }
        var tokens = self.tokens()
        guard tokens.count < Self.maxTokenCount else { return "Đã đủ \(Self.maxTokenCount) token tùy chọn." }
        tokens.append(Token(name: name, title: rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)))
        return write(tokens)
    }

    @discardableResult
    public func updateTitle(_ rawTitle: String, of name: String) -> String? {
        mutateToken(name) { $0.title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @discardableResult
    public func setEnabled(_ isEnabled: Bool, name: String) -> String? {
        mutateToken(name) { $0.isEnabled = isEnabled }
    }

    @discardableResult
    public func deleteToken(name: String) -> String? {
        var tokens = self.tokens()
        guard let index = tokens.firstIndex(where: { $0.name == name }) else { return "Token <@\(name)> không còn." }
        tokens.remove(at: index)
        return write(tokens)
    }

    // MARK: - Ghi từ

    /// Thêm (`originalKey == nil`, đứng đầu danh sách) hoặc sửa tại chỗ một từ (đổi được cả chữ gốc).
    @discardableResult
    public func saveEntry(
        key rawKey: String,
        meaning rawMeaning: String,
        in name: String,
        replacing originalKey: String?
    ) -> String? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = rawMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = keyError(key, in: name, replacing: originalKey) ?? meaningError(meaning) { return error }
        if originalKey == nil, totalEntryCount() >= Self.maxTotalEntries {
            return "Đã đủ \(Self.maxTotalEntries) từ cho mọi token tùy chọn."
        }
        return mutateToken(name) { token in
            let entry = Entry(key: key, meaning: meaning)
            if let originalKey, let index = token.entries.firstIndex(where: { $0.key == originalKey }) {
                token.entries[index] = entry
            } else {
                token.entries.insert(entry, at: 0)
            }
        }
    }

    @discardableResult
    public func deleteEntry(key: String, in name: String) -> String? {
        mutateToken(name) { $0.entries.removeAll { $0.key == key } }
    }

    // MARK: - Nhập / xuất

    /// Nhập file `chữ gốc=nghĩa` vào một token (bộ đọc chung, dòng sai bị bỏ và đếm):
    /// - **Gộp** (`overwriteExisting`): chữ trong file đè nghĩa / thêm mới (nối cuối).
    /// - **Chỉ thêm key mới** (`keepExisting`): chữ đã có giữ nguyên.
    /// - **Thay thế toàn bộ** (`replaceAll`): danh sách thành đúng nội dung file.
    /// File không có dòng hợp lệ hoặc vượt trần ⇒ ném lỗi, không đụng dữ liệu.
    public func importFile(at url: URL, into name: String, mode: DataImportMode) throws -> ImportOutcome {
        guard let text = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .utf16)) else {
            throw ImportError.unreadable
        }
        let parsed = Parser.parse(text)
        guard !parsed.entries.isEmpty else { throw ImportError.noValidLine(skipped: parsed.invalidLineCount) }

        var tokens = self.tokens()
        guard let tokenIndex = tokens.firstIndex(where: { $0.name == name }) else { throw ImportError.tokenMissing }
        let current = tokens[tokenIndex].entries
        let merged = Self.merge(current: current, imported: parsed.entries, mode: mode)

        let otherTotal = tokens.enumerated().reduce(0) { $0 + ($1.offset == tokenIndex ? 0 : $1.element.entries.count) }
        guard otherTotal + merged.entries.count <= Self.maxTotalEntries else { throw ImportError.tooManyEntries }

        tokens[tokenIndex].entries = merged.entries
        if let message = write(tokens) {
            AppLogger.shared.log("❌ [CustomToken] \(message)")
            throw ImportError.unreadable
        }
        return ImportOutcome(added: merged.added, updated: merged.updated, removed: merged.removed,
                             skipped: parsed.invalidLineCount)
    }

    /// Nội dung file xuất của một token: mọi từ, cùng dạng file nhập.
    public func exportText(of name: String) -> String {
        Parser.serialize(token(named: name)?.entries ?? [])
    }

    // MARK: - Nội bộ

    private func totalEntryCount() -> Int {
        tokens().reduce(0) { $0 + $1.entries.count }
    }

    private func mutateToken(_ name: String, _ change: (inout Token) -> Void) -> String? {
        var tokens = self.tokens()
        guard let index = tokens.firstIndex(where: { $0.name == name }) else { return "Token <@\(name)> không còn." }
        change(&tokens[index])
        return write(tokens)
    }

    private static func merge(
        current: [Entry],
        imported: [Entry],
        mode: DataImportMode
    ) -> (entries: [Entry], added: Int, updated: Int, removed: Int) {
        var indexByKey: [String: Int] = [:]
        for (index, entry) in current.enumerated() { indexByKey[entry.key] = index }

        switch mode {
        case .replaceAll:
            let fileKeys = Set(imported.map(\.key))
            let added = imported.filter { indexByKey[$0.key] == nil }.count
            let updated = imported.filter { entry in indexByKey[entry.key].map { current[$0].meaning != entry.meaning } ?? false }.count
            let removed = current.filter { !fileKeys.contains($0.key) }.count
            return (imported, added, updated, removed)

        case .overwriteExisting, .keepExisting:
            var entries = current
            var added = 0
            var updated = 0
            for entry in imported {
                if let index = indexByKey[entry.key] {
                    guard mode == .overwriteExisting, entries[index].meaning != entry.meaning else { continue }
                    entries[index].meaning = entry.meaning
                    updated += 1
                } else {
                    indexByKey[entry.key] = entries.count
                    entries.append(entry)
                    added += 1
                }
            }
            return (entries, added, updated, 0)
        }
    }

    private func markDirty() {
        lock.lock()
        isDirty = true
        lock.unlock()
    }

    private func currentCache() -> Cache {
        lock.lock()
        if !isDirty, let cache {
            lock.unlock()
            return cache
        }
        lock.unlock()

        let raw = UserDefaults.standard.string(forKey: Self.userDefaultsKey)
        lock.lock()
        defer { lock.unlock() }
        if let cache, cache.raw == raw {
            isDirty = false
            return cache
        }
        let fresh = Self.makeCache(raw: raw, tokens: Self.decode(raw))
        cache = fresh
        isDirty = false
        return fresh
    }

    /// Danh sách rỗng ⇒ xoá khoá. `nil` = đã ghi; chuỗi = lỗi.
    private func write(_ tokens: [Token]) -> String? {
        let raw: String?
        if tokens.isEmpty {
            raw = nil
            UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        } else {
            guard let data = try? JSONEncoder().encode(Payload(tokens: tokens)),
                  let encoded = String(data: data, encoding: .utf8) else {
                AppLogger.shared.log("❌ [CustomToken] Không mã hoá được danh sách token tùy chọn")
                return "Không lưu được token tùy chọn."
            }
            raw = encoded
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
        }
        let fresh = Self.makeCache(raw: raw, tokens: tokens)
        lock.lock()
        cache = fresh
        isDirty = false
        lock.unlock()
        TranslateUtils.clearCache()
        TranslationManager.shared.notifyRulesDidUpdate()
        return nil
    }

    private static func makeCache(raw: String?, tokens: [Token]) -> Cache {
        var tables: [String: Table] = [:]
        for token in tokens where token.isEnabled && !token.entries.isEmpty {
            var meanings: [String: String] = [:]
            var maxKeyLength = 0
            for entry in token.entries {
                meanings[entry.key] = entry.meaning
                maxKeyLength = max(maxKeyLength, entry.key.utf16.count)
            }
            tables[token.name] = Table(meanings: meanings, maxKeyLength: maxKeyLength)
        }
        return Cache(raw: raw, tokens: tokens, tables: tables)
    }

    /// Khoá vắng hoặc JSON hỏng ⇒ rỗng: dữ liệu hỏng không được làm hỏng lượt dịch.
    private static func decode(_ raw: String?) -> [Token] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            AppLogger.shared.log("❌ [CustomToken] Dữ liệu token tùy chọn hỏng, tạm coi như chưa có token nào")
            return []
        }
        return payload.tokens
    }
}
