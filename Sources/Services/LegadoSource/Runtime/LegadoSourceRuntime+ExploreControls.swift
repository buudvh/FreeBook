import Foundation

/// Khám phá động (spec §11) ở tầng luồng: danh sách mục **có kiểu** của `exploreUrl` (tiêu đề nhóm, ô bấm, điều khiển
/// kèm giá trị `infoMap`) cho tab lưới thể loại, cộng bộ đệm ngắn theo nguồn để màn Khám phá chỉ chạy JS `exploreUrl`
/// **một lần** khi mở nguồn (danh mục và điều khiển dựng từ cùng một kết quả).
extension LegadoSourceRuntime {
    /// Kết quả `exploreEntries` gần nhất theo nguồn (bộ nhớ, có khoá) — khoá `exploreCacheKey` gồm cả dấu vân tay JSON
    /// của nguồn, nên sửa JSON nguồn là bản đệm cũ không còn dùng được. Hết hạn sau `maxAge`; lượt chạy mới (kéo làm
    /// mới, `java.refreshExplore`) ghi đè.
    final class ExploreEntriesCache: @unchecked Sendable {
        private struct Entry {
            let items: [LegadoEngineExploreItem]
            let storedAt: Date
        }

        static let maxAge: TimeInterval = 300
        private static let capacity = 16

        private let lock = NSLock()
        private var entries: [String: Entry] = [:]
        private var running: [String: Task<[LegadoEngineExploreItem], Error>] = [:]

        /// Lượt chạy đang bay của nguồn — mở nguồn ở Khám phá thì danh mục và tab điều khiển cùng hỏi trước khi bản
        /// đệm có, nên lượt thứ hai dùng chung lượt đầu (JS `exploreUrl` không gửi request hai lần).
        func runningTask(key: String) -> Task<[LegadoEngineExploreItem], Error>? {
            lock.lock()
            defer { lock.unlock() }
            return running[key]
        }

        func setRunning(_ task: Task<[LegadoEngineExploreItem], Error>?, key: String) {
            lock.lock()
            defer { lock.unlock() }
            running[key] = task
        }

        func store(_ items: [LegadoEngineExploreItem], key: String) {
            lock.lock()
            defer { lock.unlock() }
            if entries.count >= Self.capacity, entries[key] == nil,
               let oldest = entries.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
                entries.removeValue(forKey: oldest)
            }
            entries[key] = Entry(items: items, storedAt: Date())
        }

        /// Kết quả còn hạn của nguồn, `nil` khi chưa có hoặc đã cũ.
        func items(key: String) -> [LegadoEngineExploreItem]? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[key] else { return nil }
            guard Date().timeIntervalSince(entry.storedAt) <= Self.maxAge else {
                entries.removeValue(forKey: key)
                return nil
            }
            return entry.items
        }

        /// Người dùng đổi điều khiển `title` ⇒ cập nhật `value` trong bản đệm (bản đệm không bị coi là cũ).
        func updateValue(_ value: String?, forTitle title: String, key: String) {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[key] else { return }
            var items = entry.items
            for index in items.indices where items[index].isControl && items[index].title == title {
                items[index].value = value
            }
            entries[key] = Entry(items: items, storedAt: entry.storedAt)
        }
    }

    static let exploreEntriesCache = ExploreEntriesCache()

    /// Khoá bản đệm khám phá: `packageId` + dấu vân tay JSON nguồn (sửa JSON ⇒ khoá mới).
    static func exploreCacheKey(_ target: Target) -> String {
        target.packageId + "#" + String(target.engineSource.rawJSON.hashValue)
    }

    /// Mọi mục khám phá có kiểu (spec §11.2): ô bấm, tiêu đề nhóm, điều khiển (`value` = giá trị `infoMap` hiện tại;
    /// `default` được gieo vào `infoMap` nếu khoá chưa có — §11.3 mục 2). Không có mục nào ngoài tiêu đề nhóm mà phiên có
    /// lỗi "cứng" ⇒ ném như `exploreCategories`. Kết quả được ghi vào `exploreEntriesCache`.
    ///
    /// Ngữ cảnh có người dùng do lớp gọi quyết (`LegadoInteraction`, task-local) — facade bọc khi người dùng đang xem.
    static func exploreEntries(_ target: Target, log: LegadoRunLog? = nil) async throws -> [LegadoEngineExploreItem] {
        // Nguồn không có Khám phá dùng được nhưng tìm được ⇒ danh mục tìm nhanh (không chạy engine).
        if LegadoQuickSearch.applies(to: target.source) { return LegadoQuickSearch.entries() }
        let exploreUrl = target.source.exploreUrl
        guard nonEmpty(exploreUrl) != nil else { return [] }
        let key = exploreCacheKey(target)
        // Màn gỡ lỗi (có `log`) luôn chạy riêng; lượt thường dùng chung lượt đang bay của cùng nguồn.
        if log == nil, let shared = exploreEntriesCache.runningTask(key: key) {
            return try await shared.value
        }
        // `Task {}` mang theo task-local `LegadoInteraction` của lời gọi đầu.
        let task = Task { () throws -> [LegadoEngineExploreItem] in
            try await runSession(target, log: log) { session in
                let entries = try session.exploreEntries(exploreUrl)
                if !entries.contains(where: { !$0.isGroupHeader }), Self.hasHardFailure(session) {
                    throw Self.emptyResultError(session, "exploreUrl")
                }
                return entries
            }
        }
        if log == nil { exploreEntriesCache.setRunning(task, key: key) }
        defer { if log == nil { exploreEntriesCache.setRunning(nil, key: key) } }
        let items = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        exploreEntriesCache.store(items, key: key)
        return items
    }

    /// Mục bấm được → `CategoryResult` (`input` = rule URL nguyên văn của mục, `script` = `scriptName`). Tiêu đề nhóm và
    /// điều khiển bị loại; tiêu đề trùng nhau được thêm tên nhóm phía trước để phân biệt; trùng `id` bị bỏ (ForEach cần
    /// id duy nhất). Dùng chung cho `exploreCategories` (facade `genre`) và màn Khám phá động.
    static func exploreCategories(from items: [LegadoEngineExploreItem], scriptName: String) -> [CategoryResult] {
        var titleCounts: [String: Int] = [:]
        for item in items where !item.isGroupHeader && !item.isControl {
            titleCounts[trimmed(item.title), default: 0] += 1
        }
        var output: [CategoryResult] = []
        var seenIds = Set<String>()
        var group = ""
        for item in items where !item.isControl {
            let title = trimmed(item.title)
            guard let url = item.url, nonEmpty(url) != nil else {
                if !title.isEmpty { group = title }
                continue
            }
            var display = title.isEmpty ? "Mục \(output.count + 1)" : title
            if (titleCounts[title] ?? 0) > 1, !group.isEmpty {
                display = group + " · " + display
            }
            let category = CategoryResult(title: display, input: url, script: scriptName)
            guard seenIds.insert(category.id).inserted else { continue }
            output.append(category)
        }
        return output
    }
}
