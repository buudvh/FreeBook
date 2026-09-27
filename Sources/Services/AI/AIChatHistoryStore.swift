import Foundation
import CryptoKit

/// Quản lý lưu trữ và nạp các phiên trò chuyện AI theo từng cuốn sách.
/// Mỗi phiên chat được lưu thành một file JSON độc lập để tối ưu hiệu năng I/O.
public final class AIChatHistoryStore: Sendable {
    public static let shared = AIChatHistoryStore()

    private var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ai_chats", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() {}

    private func sha256Hex(_ string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private func bookDirectory(for bookId: String) -> URL {
        let dir = storageDirectory.appendingPathComponent(sha256Hex(bookId), isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func legacyFileURL(for bookId: String) -> URL {
        let filename = "\(sha256Hex(bookId)).json"
        return storageDirectory.appendingPathComponent(filename)
    }

    private func indexFileURL(for bookId: String) -> URL {
        bookDirectory(for: bookId).appendingPathComponent("_index.json")
    }

    private func sessionFileURL(id: UUID, for bookId: String) -> URL {
        bookDirectory(for: bookId).appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Tự động Chuyển đổi (Auto-Migration)

    private func migrateLegacyFileIfNeeded(for bookId: String) {
        let legacyFile = legacyFileURL(for: bookId)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: legacyFile.path, isDirectory: &isDir), !isDir.boolValue else {
            return
        }

        guard let data = try? Data(contentsOf: legacyFile),
              let sessions = try? JSONDecoder().decode([AIChatSession].self, from: data) else {
            try? FileManager.default.removeItem(at: legacyFile)
            return
        }

        let targetDir = bookDirectory(for: bookId)
        var summaries: [AIChatSessionSummary] = []
        for session in sessions {
            let sessionFile = targetDir.appendingPathComponent("\(session.id.uuidString).json")
            if let sessionData = try? JSONEncoder().encode(session) {
                try? sessionData.write(to: sessionFile, options: .atomic)
            }
            summaries.append(AIChatSessionSummary(session: session))
        }

        let indexFile = indexFileURL(for: bookId)
        if let indexData = try? JSONEncoder().encode(summaries) {
            try? indexData.write(to: indexFile, options: .atomic)
        }

        try? FileManager.default.removeItem(at: legacyFile)
        AppLogger.shared.log("Đã chuyển đổi \(sessions.count) phiên chat AI cũ của sách \(bookId) sang cấu trúc file độc lập.")
    }

    // MARK: - Truy xuất Mục lục & Phiên Chat

    /// Nạp danh sách tóm tắt nhẹ của tất cả các phiên chat của cuốn sách.
    public func loadSessionSummaries(for bookId: String) -> [AIChatSessionSummary] {
        migrateLegacyFileIfNeeded(for: bookId)
        let indexFile = indexFileURL(for: bookId)
        if FileManager.default.fileExists(atPath: indexFile.path),
           let data = try? Data(contentsOf: indexFile),
           let summaries = try? JSONDecoder().decode([AIChatSessionSummary].self, from: data) {
            return summaries.sorted(by: { $0.updatedAt > $1.updatedAt })
        }

        // Tái tạo index từ các file session nếu _index.json chưa có
        let dir = bookDirectory(for: bookId)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        var summaries: [AIChatSessionSummary] = []
        for file in files where file.pathExtension == "json" && file.lastPathComponent != "_index.json" {
            if let data = try? Data(contentsOf: file),
               let session = try? JSONDecoder().decode(AIChatSession.self, from: data) {
                summaries.append(AIChatSessionSummary(session: session))
            }
        }
        summaries.sort(by: { $0.updatedAt > $1.updatedAt })
        persistSummaries(summaries, for: bookId)
        return summaries
    }

    /// Tải duy nhất một phiên chat cụ thể theo ID.
    public func loadSession(id: UUID, for bookId: String) -> AIChatSession? {
        migrateLegacyFileIfNeeded(for: bookId)
        let file = sessionFileURL(id: id, for: bookId)
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let session = try? JSONDecoder().decode(AIChatSession.self, from: data) else {
            return nil
        }
        return session
    }

    /// Tải toàn bộ danh sách phiên chat đầy đủ của một cuốn sách (dùng khi cần nạp hết).
    public func loadSessions(for bookId: String) -> [AIChatSession] {
        let summaries = loadSessionSummaries(for: bookId)
        var result: [AIChatSession] = []
        for s in summaries {
            if let session = loadSession(id: s.id, for: bookId) {
                result.append(session)
            }
        }
        return result
    }

    /// Lưu hoặc cập nhật một phiên chat.
    public func saveSession(_ session: AIChatSession, for bookId: String) {
        migrateLegacyFileIfNeeded(for: bookId)
        let file = sessionFileURL(id: session.id, for: bookId)
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: file, options: .atomic)
        } catch {
            AppLogger.shared.log("Lỗi lưu phiên chat \(session.id) cho sách \(bookId): \(error.localizedDescription)")
        }

        var summaries = loadSessionSummaries(for: bookId)
        let newSummary = AIChatSessionSummary(session: session)
        if let idx = summaries.firstIndex(where: { $0.id == session.id }) {
            summaries[idx] = newSummary
        } else {
            summaries.insert(newSummary, at: 0)
        }
        persistSummaries(summaries, for: bookId)
    }

    /// Xóa một phiên chat cụ thể.
    public func deleteSession(sessionId: UUID, for bookId: String) {
        let file = sessionFileURL(id: sessionId, for: bookId)
        try? FileManager.default.removeItem(at: file)

        var summaries = loadSessionSummaries(for: bookId)
        summaries.removeAll(where: { $0.id == sessionId })
        persistSummaries(summaries, for: bookId)
    }

    /// Xóa toàn bộ lịch sử phiên chat của cuốn sách.
    public func clearAllSessions(for bookId: String) {
        let dir = bookDirectory(for: bookId)
        try? FileManager.default.removeItem(at: dir)
        let legacyFile = legacyFileURL(for: bookId)
        try? FileManager.default.removeItem(at: legacyFile)
    }

    /// Xóa toàn bộ lịch sử phiên chat của tất cả các cuốn sách trong app.
    public func clearAllSessionsAcrossAllBooks() {
        let dir = storageDirectory
        if let subdirs = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in subdirs {
                try? FileManager.default.removeItem(at: item)
            }
        }
        AppLogger.shared.log("Đã dọn dẹp toàn bộ lịch sử phiên chat AI của tất cả truyện.")
    }

    /// Tải danh sách tóm tắt của tất cả các phiên chat trên toàn app.
    public func loadAllSessionsAcrossAllBooks() -> [AIChatSessionSummary] {
        let dir = storageDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        var allSummaries: [AIChatSessionSummary] = []
        for item in items {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    let indexFile = item.appendingPathComponent("_index.json")
                    if let data = try? Data(contentsOf: indexFile),
                       let summaries = try? JSONDecoder().decode([AIChatSessionSummary].self, from: data) {
                        allSummaries.append(contentsOf: summaries)
                    }
                } else if item.pathExtension == "json" {
                    // File legacy
                    if let data = try? Data(contentsOf: item),
                       let sessions = try? JSONDecoder().decode([AIChatSession].self, from: data) {
                        for s in sessions {
                            allSummaries.append(AIChatSessionSummary(session: s))
                        }
                    }
                }
            }
        }
        return allSummaries.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    /// Chuyển toàn bộ phiên chat từ sách cũ sang sách mới khi đổi nguồn.
    public func migrateSessions(from oldBookId: String, to newBookId: String) {
        guard oldBookId != newBookId else { return }
        let oldSessions = loadSessions(for: oldBookId)
        guard !oldSessions.isEmpty else { return }

        for session in oldSessions {
            var migrated = session
            migrated.updatedAt = Date()
            saveSession(migrated, for: newBookId)
        }
        clearAllSessions(for: oldBookId)
        AppLogger.shared.log("Đã chuyển \(oldSessions.count) phiên chat AI từ \(oldBookId) sang \(newBookId).")
    }

    private func persistSummaries(_ summaries: [AIChatSessionSummary], for bookId: String) {
        let indexFile = indexFileURL(for: bookId)
        do {
            let data = try JSONEncoder().encode(summaries)
            try data.write(to: indexFile, options: .atomic)
        } catch {
            AppLogger.shared.log("Lỗi lưu mục lục AI chat cho sách \(bookId): \(error.localizedDescription)")
        }
    }
}
