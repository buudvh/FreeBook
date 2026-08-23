import Foundation

/// Chủ sở hữu **duy nhất** của `applicationSupportDirectory/new_chapters.json` — file lưu trạng thái
/// theo dõi chương mới của từng truyện.
///
/// Ghi bằng `.atomic` để lần ghi bị cắt giữa (app bị kill) không để lại file JSON hỏng; đọc lỗi thì coi
/// như chưa có dữ liệu, vì mọi thứ trong đây đều dựng lại được bằng một lần kiểm tra mục lục.
actor NewChapterStore {
    static let shared = NewChapterStore()

    private var records: [String: NewChapterRecord]?

    private init() {}

    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("new_chapters.json")
    }

    /// Toàn bộ record, nạp từ đĩa ở lần gọi đầu tiên.
    func all() -> [String: NewChapterRecord] {
        if let records {
            return records
        }
        let loaded = loadFromDisk()
        records = loaded
        return loaded
    }

    func record(for bookId: String) -> NewChapterRecord? {
        all()[bookId]
    }

    /// Ghi đè record của một truyện rồi lưu xuống đĩa.
    func save(_ record: NewChapterRecord) {
        var current = all()
        current[record.bookId] = record
        records = current
        persist(current)
    }

    /// Ghi một loạt record trong **một** lần lưu file — dùng cho batch kiểm tra nhiều truyện.
    func save(_ batch: [NewChapterRecord]) {
        guard !batch.isEmpty else { return }
        var current = all()
        for record in batch {
            current[record.bookId] = record
        }
        records = current
        persist(current)
    }

    func remove(bookId: String) {
        var current = all()
        guard current.removeValue(forKey: bookId) != nil else { return }
        records = current
        persist(current)
    }

    /// Xoá record của truyện không còn trên kệ để file không phình theo thời gian.
    /// Trả về `true` khi có thay đổi.
    func prune(keeping bookIds: Set<String>) -> Bool {
        var current = all()
        let stale = current.keys.filter { !bookIds.contains($0) }
        guard !stale.isEmpty else { return false }
        for key in stale {
            current.removeValue(forKey: key)
        }
        records = current
        persist(current)
        return true
    }

    private func loadFromDisk() -> [String: NewChapterRecord] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([String: NewChapterRecord].self, from: data)
            // Record thiếu bookId (file bản cũ hoặc bị sửa tay) lấy lại từ khoá của dictionary.
            return decoded.reduce(into: [:]) { result, pair in
                var record = pair.value
                if record.bookId.isEmpty {
                    record.bookId = pair.key
                }
                result[pair.key] = record
            }
        } catch {
            AppLogger.shared.log("[NewChapterStore] Không đọc được new_chapters.json: \(error.localizedDescription)")
            return [:]
        }
    }

    private func persist(_ records: [String: NewChapterRecord]) {
        let url = fileURL
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("[NewChapterStore] Không ghi được new_chapters.json: \(error.localizedDescription)")
        }
    }
}
