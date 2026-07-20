import Foundation
import CryptoKit

public actor BookBinManager {
    public static let shared = BookBinManager()

    private let fileManager = FileManager.default

    private var booksDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("books", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }

    private init() {}

    private func sha256Hex(_ string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private func validatePathSafety(for targetURL: URL) throws {
        let canonicalRoot = booksDirectory.standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        guard canonicalTarget.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw NSError(domain: "SecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Truy cập file ngoài thư mục Sandbox bị từ chối."])
        }
    }

    private func migrateLegacyFileIfNecessary(for bookId: String) {
        let newURL = booksDirectory.appendingPathComponent(sha256Hex(bookId) + ".bin")
        let oldURL = booksDirectory.appendingPathComponent("\(bookId).bin")

        guard (try? validatePathSafety(for: newURL)) != nil,
              (try? validatePathSafety(for: oldURL)) != nil else {
            return
        }

        let newExist = fileManager.fileExists(atPath: newURL.path)
        let oldExist = fileManager.fileExists(atPath: oldURL.path)

        if oldExist && !newExist {
            do {
                try fileManager.moveItem(at: oldURL, to: newURL)
                AppLogger.shared.log("🚚 Di chuyển thành công file .bin cũ sang định dạng SHA-256 mới cho sách: \(bookId)")
            } catch {
                AppLogger.shared.log("❌ Lỗi di chuyển file .bin cũ sang mới: \(error.localizedDescription)")
            }
        } else if oldExist && newExist {
            do {
                try fileManager.removeItem(at: oldURL)
            } catch {
                AppLogger.shared.log("❌ Lỗi dọn dẹp file .bin cũ trùng lặp: \(error.localizedDescription)")
                let retryQueueKey = "failed_file_deletions_queue"
                var queue = UserDefaults.standard.stringArray(forKey: retryQueueKey) ?? []
                if !queue.contains(oldURL.path) {
                    queue.append(oldURL.path)
                    UserDefaults.standard.set(queue, forKey: retryQueueKey)
                }
            }
        }
    }

    public func binFilePath(for bookId: String) -> URL {
        migrateLegacyFileIfNecessary(for: bookId)
        return booksDirectory.appendingPathComponent(sha256Hex(bookId) + ".bin")
    }

    public func readChapterContent(bookId: String, offset: Int64, length: Int64) throws -> String {
        guard length > 0 else { return "" }
        let fileURL = binFilePath(for: bookId)

        try validatePathSafety(for: fileURL)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "BookBinManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "File .bin không tồn tại cho sách \(bookId)"])
        }

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        try fileHandle.seek(toOffset: UInt64(offset))
        guard let data = try fileHandle.read(upToCount: Int(length)) else {
            throw NSError(domain: "BookBinManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Không thể đọc dữ liệu tại offset \(offset)"])
        }

        if let content = String(data: data, encoding: .utf8) {
            return content
        }
        throw NSError(domain: "BookBinManager", code: 501, userInfo: [NSLocalizedDescriptionKey: "Lỗi giải mã UTF-8 cho chương truyện"])
    }

    public func writeChapterContent(bookId: String, content: String) throws -> (offset: Int64, length: Int64) {
        let fileURL = binFilePath(for: bookId)

        try validatePathSafety(for: fileURL)

        let data = Data(content.utf8)
        let length = Int64(data.count)

        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer { try? fileHandle.close() }

        try fileHandle.seekToEnd()
        let offset = Int64(try fileHandle.offset())
        try fileHandle.write(contentsOf: data)

        return (offset: offset, length: length)
    }

    public func deleteBinFile(for bookId: String) throws {
        let fileURL = binFilePath(for: bookId)
        let oldURL = booksDirectory.appendingPathComponent("\(bookId).bin")

        try validatePathSafety(for: fileURL)
        try validatePathSafety(for: oldURL)

        var deletionError: Error? = nil

        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
                AppLogger.shared.log("🗑️ Đã xóa thành công file .bin mới: \(fileURL.path)")
            } catch {
                deletionError = error
                AppLogger.shared.log("❌ Lỗi xóa file .bin mới: \(error.localizedDescription)")
            }
        }

        if fileManager.fileExists(atPath: oldURL.path) {
            do {
                try fileManager.removeItem(at: oldURL)
                AppLogger.shared.log("🗑️ Đã xóa thành công file .bin cũ: \(oldURL.path)")
            } catch {
                if deletionError == nil {
                    deletionError = error
                }
                AppLogger.shared.log("❌ Lỗi xóa file .bin cũ: \(error.localizedDescription)")
            }
        }

        if let error = deletionError {
            throw error
        }
    }
}
