import Foundation

/// Chủ sở hữu **duy nhất** của `applicationSupportDirectory/notifications.json` — nhật ký toast đã hiện.
///
/// Ghi `.atomic` để lần ghi bị cắt giữa (app bị kill) không để lại file hỏng; đọc lỗi coi như rỗng.
/// Giữ tối đa `maxRecords` dòng (drop cũ nhất) để file không phình theo thời gian. Mẫu bám sát
/// [`NewChapterStore`](../../Services/NewChapters/NewChapterStore.swift).
actor NotificationInboxStore {
    static let shared = NotificationInboxStore()

    /// Trần số dòng giữ lại; vượt thì bỏ dòng cũ nhất.
    static let maxRecords = 200

    private var cached: [NotificationInboxRecord]?

    private init() {}

    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("notifications.json")
    }

    /// Toàn bộ record (mới nhất trước), nạp từ đĩa ở lần gọi đầu.
    func all() -> [NotificationInboxRecord] {
        if let cached {
            return cached
        }
        let loaded = loadFromDisk()
        cached = loaded
        return loaded
    }

    /// Thêm một record mới lên đầu, cắt bớt theo trần, rồi lưu. Trả về danh sách sau khi thêm.
    func append(_ record: NotificationInboxRecord) -> [NotificationInboxRecord] {
        var current = all()
        current.insert(record, at: 0)
        if current.count > Self.maxRecords {
            current = Array(current.prefix(Self.maxRecords))
        }
        cached = current
        persist(current)
        return current
    }

    /// Ghi đè toàn bộ (dùng cho đánh dấu đã đọc / xoá một dòng).
    func replace(with records: [NotificationInboxRecord]) {
        let trimmed = records.count > Self.maxRecords ? Array(records.prefix(Self.maxRecords)) : records
        cached = trimmed
        persist(trimmed)
    }

    func clearAll() {
        cached = []
        persist([])
    }

    private func loadFromDisk() -> [NotificationInboxRecord] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([NotificationInboxRecord].self, from: data)
        } catch {
            AppLogger.shared.log("[NotificationInboxStore] Không đọc được notifications.json: \(error.localizedDescription)")
            return []
        }
    }

    private func persist(_ records: [NotificationInboxRecord]) {
        let url = fileURL
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("[NotificationInboxStore] Không ghi được notifications.json: \(error.localizedDescription)")
        }
    }
}
