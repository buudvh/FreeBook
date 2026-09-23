import Foundation
import CryptoKit

/// Quản lý lưu trữ và nạp trí nhớ dài hạn (BookAIMemory) của từng cuốn truyện.
public final class BookAIMemoryStore: Sendable {
    public static let shared = BookAIMemoryStore()

    private var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ai_memory", isDirectory: true)
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

    /// Tải trí nhớ của cuốn truyện. Nếu chưa có, trả về BookAIMemory rỗng mới.
    public func loadMemory(for bookId: String) -> BookAIMemory {
        let url = fileURL(for: bookId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let memory = try? JSONDecoder().decode(BookAIMemory.self, from: data) else {
            return BookAIMemory(bookId: bookId)
        }
        return memory
    }

    /// Lưu hoặc cập nhật trí nhớ của cuốn truyện.
    public func saveMemory(_ memory: BookAIMemory) {
        let url = fileURL(for: memory.bookId)
        var toSave = memory
        toSave.updatedAt = Date()
        do {
            let data = try JSONEncoder().encode(toSave)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("Lỗi lưu trí nhớ AI cho sách \(memory.bookId): \(error.localizedDescription)")
        }
    }

    /// Xóa trí nhớ của cuốn truyện.
    public func clearMemory(for bookId: String) {
        let url = fileURL(for: bookId)
        try? FileManager.default.removeItem(at: url)
    }
}
