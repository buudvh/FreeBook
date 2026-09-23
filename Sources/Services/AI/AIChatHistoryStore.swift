import Foundation
import CryptoKit

/// Quản lý lưu trữ và nạp các phiên trò chuyện AI theo từng cuốn sách.
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

    private func fileURL(for bookId: String) -> URL {
        let filename = "\(sha256Hex(bookId)).json"
        return storageDirectory.appendingPathComponent(filename)
    }

    /// Tải toàn bộ danh sách phiên chat của một cuốn sách.
    public func loadSessions(for bookId: String) -> [AIChatSession] {
        let url = fileURL(for: bookId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let sessions = try? JSONDecoder().decode([AIChatSession].self, from: data) else {
            return []
        }
        return sessions.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    /// Lưu hoặc cập nhật một phiên chat.
    public func saveSession(_ session: AIChatSession, for bookId: String) {
        var sessions = loadSessions(for: bookId)
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
        persistSessions(sessions, for: bookId)
    }

    /// Xóa một phiên chat cụ thể.
    public func deleteSession(sessionId: UUID, for bookId: String) {
        var sessions = loadSessions(for: bookId)
        sessions.removeAll(where: { $0.id == sessionId })
        persistSessions(sessions, for: bookId)
    }

    /// Xóa toàn bộ lịch sử phiên chat của cuốn sách.
    public func clearAllSessions(for bookId: String) {
        let url = fileURL(for: bookId)
        try? FileManager.default.removeItem(at: url)
    }

    private func persistSessions(_ sessions: [AIChatSession], for bookId: String) {
        let url = fileURL(for: bookId)
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("Lỗi lưu lịch sử AI chat cho sách \(bookId): \(error.localizedDescription)")
        }
    }
}
