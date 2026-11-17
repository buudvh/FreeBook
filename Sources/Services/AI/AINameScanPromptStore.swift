import Foundation

/// Prompt tự nhập đã lưu của sheet "Quét tên riêng theo phạm vi": **Gần đây theo truyện** (tối đa `recentLimit`, dùng
/// gần nhất lên đầu) và **Đã ghim dùng chung** mọi truyện (mới ghim lên đầu, không giới hạn).
///
/// - Chỉ lưu chữ trong ô "Prompt cho lần này" (đã cắt khoảng trắng hai đầu), không bao giờ kèm nội dung truyện.
/// - So trùng bằng **toàn bộ** chuỗi: gửi lại prompt đã có ⇒ đưa lên đầu, không thêm bản thứ hai. Prompt trùng prompt
///   Cài đặt hay trùng một bản đã ghim thì không ghi vào Gần đây; Gần đây hiện ra luôn lọc bỏ chữ trùng bản ghim.
/// - Khoá UserDefaults viết thường chữ đầu ⇒ tự vào khối cài đặt của Sao lưu (`BackupSettingsArchiver.isExportable`).
/// - Gần đây khoá theo `bookId` ⇒ chép / xoá khi đổi nguồn ở `BookSourceMigrator` (`copy` / `remove`).
///
/// Sheet gọi trên main, `BookSourceMigrator` là actor ⇒ mọi đọc-sửa-ghi đi qua `lock`.
public final class AINameScanPromptStore: @unchecked Sendable {
    public static let shared = AINameScanPromptStore()

    /// Số prompt Gần đây giữ cho mỗi truyện.
    public static let recentLimit = 10

    private static let recentsKey = "aiNameScanPromptRecents"
    private static let pinsKey = "aiNameScanPromptPins"

    private let lock = NSLock()

    private init() {}

    // MARK: - Đọc

    public func pins() -> [AINameScanSavedPrompt] {
        lock.lock()
        defer { lock.unlock() }
        return loadPins()
    }

    /// Gần đây của truyện, đã bỏ những prompt trùng chữ với một bản ghim.
    public func recents(bookId: String) -> [AINameScanSavedPrompt] {
        lock.lock()
        defer { lock.unlock() }
        return visibleRecents(bookId: bookId, pins: loadPins())
    }

    /// Số bản ghim và số bản Gần đây (đã lọc) của truyện — phụ đề dòng "Chọn prompt đã lưu…".
    public func counts(bookId: String) -> (pinned: Int, recent: Int) {
        lock.lock()
        defer { lock.unlock() }
        let pins = loadPins()
        return (pins.count, visibleRecents(bookId: bookId, pins: pins).count)
    }

    // MARK: - Ghi

    /// Gọi lúc bấm "Bắt đầu quét" với nguồn Tự nhập prompt.
    public func recordUse(_ text: String, bookId: String, settingsPrompt: String) {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty, normalized != Self.normalize(settingsPrompt) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !loadPins().contains(where: { $0.text == normalized }) else { return }
        var all = loadRecents()
        all[bookId] = Self.inserting(AINameScanSavedPrompt(text: normalized), into: all[bookId] ?? [])
        saveRecents(all)
        AppLogger.shared.log("📝 [AIPrompt] Nhớ prompt quét tên (\(normalized.count) ký tự), Gần đây của truyện: \(all[bookId]?.count ?? 0)")
    }

    /// Chuyển một prompt từ Gần đây của truyện sang Đã ghim (đầu danh sách).
    public func pin(id: UUID, bookId: String) {
        lock.lock()
        defer { lock.unlock() }
        var all = loadRecents()
        guard var list = all[bookId], let index = list.firstIndex(where: { $0.id == id }) else { return }
        var prompt = list.remove(at: index)
        all[bookId] = list.isEmpty ? nil : list
        saveRecents(all)

        var pins = loadPins()
        guard !pins.contains(where: { $0.text == prompt.text }) else { return }
        prompt.lastUsedAt = Date()
        pins.insert(prompt, at: 0)
        savePins(pins)
    }

    /// Bỏ ghim ⇒ prompt về đầu Gần đây của truyện đang mở (đủ `recentLimit` thì bản cũ nhất rơi).
    public func unpin(id: UUID, bookId: String) {
        lock.lock()
        defer { lock.unlock() }
        var pins = loadPins()
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        var prompt = pins.remove(at: index)
        savePins(pins)

        prompt.lastUsedAt = Date()
        var all = loadRecents()
        all[bookId] = Self.inserting(prompt, into: all[bookId] ?? [])
        saveRecents(all)
    }

    /// Xoá hẳn — bản ghim thì mất ở mọi truyện.
    public func delete(id: UUID, bookId: String) {
        lock.lock()
        defer { lock.unlock() }
        var pins = loadPins()
        if let index = pins.firstIndex(where: { $0.id == id }) {
            pins.remove(at: index)
            savePins(pins)
            return
        }
        var all = loadRecents()
        guard var list = all[bookId], let index = list.firstIndex(where: { $0.id == id }) else { return }
        list.remove(at: index)
        all[bookId] = list.isEmpty ? nil : list
        saveRecents(all)
    }

    // MARK: - Đổi nguồn

    /// Chép Gần đây sang truyện đích; truyện đích đã có thì giữ của đích (như `AINameScanScopeStore.copy`).
    public func copy(from oldBookId: String, to newBookId: String) {
        guard oldBookId != newBookId else { return }
        lock.lock()
        defer { lock.unlock() }
        var all = loadRecents()
        guard let list = all[oldBookId], !list.isEmpty, all[newBookId] == nil else { return }
        all[newBookId] = list
        saveRecents(all)
    }

    public func remove(bookId: String) {
        lock.lock()
        defer { lock.unlock() }
        var all = loadRecents()
        guard all[bookId] != nil else { return }
        all[bookId] = nil
        saveRecents(all)
    }

    // MARK: - Nội bộ (gọi khi đang giữ `lock`)

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bỏ bản trùng chữ, chèn đầu, cắt còn `recentLimit`.
    private static func inserting(_ prompt: AINameScanSavedPrompt, into list: [AINameScanSavedPrompt]) -> [AINameScanSavedPrompt] {
        var result = list.filter { $0.text != prompt.text }
        result.insert(prompt, at: 0)
        return Array(result.prefix(recentLimit))
    }

    private func visibleRecents(bookId: String, pins: [AINameScanSavedPrompt]) -> [AINameScanSavedPrompt] {
        let pinnedTexts = Set(pins.map(\.text))
        return (loadRecents()[bookId] ?? []).filter { !pinnedTexts.contains($0.text) }
    }

    private func loadRecents() -> [String: [AINameScanSavedPrompt]] {
        decode([String: [AINameScanSavedPrompt]].self, key: Self.recentsKey) ?? [:]
    }

    private func loadPins() -> [AINameScanSavedPrompt] {
        decode([AINameScanSavedPrompt].self, key: Self.pinsKey) ?? []
    }

    private func saveRecents(_ value: [String: [AINameScanSavedPrompt]]) {
        encode(value, key: Self.recentsKey)
    }

    private func savePins(_ value: [AINameScanSavedPrompt]) {
        encode(value, key: Self.pinsKey)
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            AppLogger.shared.log("❌ [AIPrompt] Không đọc được \(key), coi như rỗng: \(error.localizedDescription)")
            return nil
        }
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            AppLogger.shared.log("❌ [AIPrompt] Không ghi được \(key): \(error.localizedDescription)")
        }
    }
}
