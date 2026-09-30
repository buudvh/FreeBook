import Foundation

/// Tầng rule **riêng theo truyện** của `TTSReplacementManager`.
///
/// Tách khỏi file chính vì `TTSReplacementManager.swift` ở **391/400** dòng. Extension cùng module nên dùng
/// được các thành viên đã hạ `private` → `internal` ở file chính (`ReplacementStep`, `planLock`,
/// `compile(_:)`) — Swift giới hạn `private` **theo file**, không theo type.
///
/// **Luật gộp** (user chốt 2026-09-30): rule của truyện **đè** rule chung theo `pattern` và đứng trước;
/// rule riêng đang **tắt** vẫn **chặn** rule chung cùng `pattern` (kiểu tombstone). Vì vậy tập `pattern` để
/// chặn được tính trên **toàn bộ** rule riêng — kể cả rule tắt — còn bước biên dịch vẫn lọc `isEnabled` như
/// cũ, nên rule tắt không bao giờ lọt vào kế hoạch.
///
/// **Lưu trữ**: `translate/books/<bookId>/character_replacements.json` — cùng gốc `translate/` với từ điển
/// riêng truyện, nên dùng lại được cả backup lẫn luồng đổi nguồn (`TranslationManager.bookScopedTTSFiles`).
extension TTSReplacementManager {

    /// Tên file rule riêng, khai một chỗ cho cả tầng lưu trữ, backup và đổi nguồn.
    static let bookRulesFileName = "character_replacements.json"

    // MARK: - Đọc / ghi

    /// Đường dẫn file rule riêng của một truyện.
    func bookRulesURL(bookId: String) -> URL {
        TranslationManager.shared.translateDirectory
            .appendingPathComponent("books", isDirectory: true)
            .appendingPathComponent(bookId, isDirectory: true)
            .appendingPathComponent(Self.bookRulesFileName)
    }

    /// Rule riêng của truyện (đọc đĩa một lần rồi cache). `nil`/rỗng ⇒ mảng rỗng, tức không có tầng riêng.
    func rules(bookId: String?) -> [TTSReplacementRule] {
        guard let bookId, !bookId.isEmpty else { return [] }
        bookCacheLock.lock()
        if let cached = bookRulesCache[bookId] {
            bookCacheLock.unlock()
            return cached
        }
        bookCacheLock.unlock()

        let loaded = Self.readRules(from: bookRulesURL(bookId: bookId))
        bookCacheLock.lock()
        bookRulesCache[bookId] = loaded
        bookCacheLock.unlock()
        return loaded
    }

    /// Nạp lại rule riêng từ đĩa (bỏ cache) — dùng sau khi import/khôi phục backup ghi thẳng vào file.
    func loadRules(bookId: String?) {
        guard let bookId, !bookId.isEmpty else { return }
        let loaded = Self.readRules(from: bookRulesURL(bookId: bookId))
        bookCacheLock.lock()
        bookRulesCache[bookId] = loaded
        bookCacheLock.unlock()
        invalidateBookPlans()
    }

    /// Ghi rule riêng ra đĩa. Danh sách rỗng ⇒ **xoá file** để `translate/books/<bookId>/` không còn rác.
    func saveRules(bookId: String?) {
        guard let bookId, !bookId.isEmpty else {
            saveRules()
            return
        }
        let list = rules(bookId: bookId)
        let url = bookRulesURL(bookId: bookId)
        if list.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(list)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ Lỗi lưu rule thay thế riêng (\(bookId)): \(error.localizedDescription)")
        }
    }

    // MARK: - Kế hoạch đã gộp

    /// Danh sách rule **đã gộp** cho một truyện: rule riêng (giữ nguyên thứ tự, **gồm cả rule đang tắt**)
    /// rồi tới rule chung chưa bị `pattern` nào của truyện đè. Truyện không có rule riêng ⇒ trả nguyên
    /// `rules` (đường đi y hệt trước khi có tính năng này).
    func mergedRules(bookId: String?) -> [TTSReplacementRule] {
        let local = rules(bookId: bookId)
        guard !local.isEmpty else { return rules }
        let blocked = Set(local.map(\.pattern))
        return local + rules.filter { !blocked.contains($0.pattern) }
    }

    /// Kế hoạch đã biên dịch cho một truyện — dựng **lười** rồi cache.
    ///
    /// `bookId` nil/rỗng ⇒ trả kế hoạch chung đã có (`replacementPlan`), không đi qua cache theo truyện.
    func plan(forBookId bookId: String?) -> [ReplacementStep] {
        guard let bookId, !bookId.isEmpty else {
            planLock.lock()
            let global = replacementPlan
            planLock.unlock()
            return global
        }
        planLock.lock()
        if let cached = bookPlansCache[bookId] {
            planLock.unlock()
            return cached
        }
        planLock.unlock()

        // Dựng **ngoài** lock vì đọc file là I/O. Hai luồng cùng dựng một truyện cho cùng kết quả nên vô hại.
        let compiled = Self.compile(mergedRules(bookId: bookId))
        planLock.lock()
        bookPlansCache[bookId] = compiled
        planLock.unlock()
        return compiled
    }

    /// Xoá **mọi** kế hoạch cache theo truyện.
    ///
    /// Gọi khi rule **chung** đổi (`rebuildReplacementPlan`) hoặc khi rule của một truyện đổi: rule chung
    /// nằm trong kế hoạch của mọi truyện, nên không thể chỉ xoá đúng một khoá. Rule riêng vẫn còn trong
    /// `bookRulesCache` nên lần đọc kế tiếp **không** phải đọc đĩa lại.
    func invalidateBookPlans() {
        planLock.lock()
        bookPlansCache.removeAll()
        planLock.unlock()
    }

    // MARK: - CRUD theo tầng

    @discardableResult
    func addRule(_ rule: TTSReplacementRule, bookId: String?) -> AddRuleResult {
        guard let bookId, !bookId.isEmpty else { return addRule(rule) }
        var list = rules(bookId: bookId)
        let previousCount = list.count
        list.removeAll { $0.pattern == rule.pattern }
        let replacedExisting = list.count != previousCount
        list.append(rule)
        store(list, bookId: bookId)
        return replacedExisting ? .replaced : .added
    }

    func updateRule(_ rule: TTSReplacementRule, bookId: String?) {
        guard let bookId, !bookId.isEmpty else {
            updateRule(rule)
            return
        }
        var list = rules(bookId: bookId)
        guard let index = list.firstIndex(where: { $0.id == rule.id }) else { return }
        list[index] = rule
        store(list, bookId: bookId)
    }

    func deleteRule(id: UUID, bookId: String?) {
        guard let bookId, !bookId.isEmpty else {
            deleteRule(id: id)
            return
        }
        var list = rules(bookId: bookId)
        list.removeAll { $0.id == id }
        store(list, bookId: bookId)
    }

    func moveRules(from source: IndexSet, to destination: Int, bookId: String?) {
        guard let bookId, !bookId.isEmpty else {
            moveRules(from: source, to: destination)
            return
        }
        var list = rules(bookId: bookId)
        list.move(fromOffsets: source, toOffset: destination)
        store(list, bookId: bookId)
    }

    func exportRulesToJSON(bookId: String?) -> String? {
        guard let bookId, !bookId.isEmpty else { return exportRulesToJSON() }
        guard let data = try? JSONEncoder().encode(rules(bookId: bookId)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func importRules(fromJSONString jsonString: String, mode: ImportMode, bookId: String?) -> Bool {
        guard let bookId, !bookId.isEmpty else {
            return importRules(fromJSONString: jsonString, mode: mode)
        }
        guard let data = jsonString.data(using: .utf8),
              let imported = try? JSONDecoder().decode([TTSReplacementRule].self, from: data) else {
            AppLogger.shared.log("❌ Lỗi import rule thay thế riêng (\(bookId)): JSON không đọc được")
            return false
        }
        var list = rules(bookId: bookId)
        switch mode {
        case .overwrite:
            list = imported
        case .merge:
            // Cùng ngữ nghĩa `merge` của tầng chung: chỉ nối rule có `pattern` **chưa** tồn tại.
            for rule in imported where !list.contains(where: { $0.pattern == rule.pattern }) {
                list.append(rule)
            }
        }
        store(list, bookId: bookId)
        return true
    }

    /// Ghi danh sách mới vào cache → xoá kế hoạch đã biên dịch → ghi đĩa. Mọi thao tác CRUD đi qua đây.
    private func store(_ list: [TTSReplacementRule], bookId: String) {
        bookCacheLock.lock()
        bookRulesCache[bookId] = list
        bookCacheLock.unlock()
        invalidateBookPlans()
        saveRules(bookId: bookId)
    }

    private static func readRules(from url: URL) -> [TTSReplacementRule] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TTSReplacementRule].self, from: data) else {
            return []
        }
        return decoded
    }
}

// MARK: - Cache

/// Cache rule riêng theo truyện. `applyReplacements` chạy trên thread nền (tổng hợp TTS, `scheduleNghiRefill`)
/// nên đọc/ghi phải qua lock — cùng mô hình với `replacementPlan` ở file chính.
private let bookCacheLock = NSLock()
private nonisolated(unsafe) var bookRulesCache: [String: [TTSReplacementRule]] = [:]
/// Kế hoạch đã biên dịch theo truyện; bảo vệ bằng **`planLock` của file chính** (cùng một lock cho mọi
/// trạng thái kế hoạch, tránh hai lock lồng nhau).
private nonisolated(unsafe) var bookPlansCache: [String: [TTSReplacementManager.ReplacementStep]] = [:]
