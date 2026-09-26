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

    /// Tự động đồng bộ âm thầm dữ liệu truyện và từ điển vào trí nhớ của AI.
    public func syncWithBookData(bookId: String, desc: String? = nil) {
        var memory = loadMemory(for: bookId)
        var changed = false

        if memory.characterContext.isEmpty, let descText = desc?.trimmingCharacters(in: .whitespacesAndNewlines), !descText.isEmpty {
            memory.characterContext = descText
            changed = true
        }

        let dictContext = AIBookDataInspector.shared.fetchBookDictionaryContext(bookId: bookId)
        if !dictContext.isEmpty && dictContext != memory.customDictionarySnapshot {
            memory.customDictionarySnapshot = dictContext
            changed = true
        }

        if changed {
            saveMemory(memory)
        }
    }

    /// Di chuyển trí nhớ AI khi đổi nguồn truyện.
    public func migrateMemory(from oldBookId: String, to newBookId: String) {
        let oldUrl = fileURL(for: oldBookId)
        let newUrl = fileURL(for: newBookId)
        guard FileManager.default.fileExists(atPath: oldUrl.path) else { return }

        try? FileManager.default.removeItem(at: newUrl)
        do {
            try FileManager.default.copyItem(at: oldUrl, to: newUrl)
            try? FileManager.default.removeItem(at: oldUrl)
            var mem = loadMemory(for: newBookId)
            let updated = BookAIMemory(
                id: mem.id,
                bookId: newBookId,
                characterContext: mem.characterContext,
                plotSummary: mem.plotSummary,
                customDictionarySnapshot: mem.customDictionarySnapshot,
                notes: mem.notes,
                updatedAt: Date()
            )
            saveMemory(updated)
            AppLogger.shared.log("Đã di chuyển trí nhớ AI từ \(oldBookId) sang \(newBookId)")
        } catch {
            AppLogger.shared.log("Lỗi di chuyển trí nhớ AI: \(error.localizedDescription)")
        }
    }

    /// Xóa trí nhớ của cuốn truyện.
    public func clearMemory(for bookId: String) {
        let url = fileURL(for: bookId)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Trí nhớ tổng (Global AI Memory)

    public static let defaultGlobalMemoryPrompt = """
    # QUY TẮC PHÂN TÍCH VÀ TRÍCH XUẤT TÊN RIÊNG:
    Khi người dùng yêu cầu trích xuất tên riêng, tìm danh từ riêng, lọc tên nhân vật hoặc kiểm tra từ điển từ đoạn văn bản/chương truyện:
    1. Chỉ trích xuất các danh từ riêng thực sự (Tên nhân vật, địa danh, tông môn, công pháp, bảo vật đặc thù). Bỏ qua các danh từ chung thông thường (ví dụ: sư phụ, chưởng môn, đệ tử, thanh niên, thiếu nữ, hoàng đế,...).
    2. Đối với mỗi tên riêng tìm thấy, hãy đối chiếu và chuyển ngữ sang tên Hán Việt chuẩn, tự nhiên nhất.
    3. Trả về kết quả dưới dạng một mảng JSON thuần túy (không bọc trong markdown code block, hoặc đặt trong block json) theo định dạng:
    [
      {"original": "Tên gốc chữ Hán", "suggestedMeaning": "Tên Hán Việt đề xuất"}
    ]
    Không kèm theo lời dẫn rườm rà nếu được yêu cầu lọc dữ liệu tự động.
    """

    private var globalMemoryURL: URL {
        storageDirectory.appendingPathComponent("global_memory.txt")
    }

    /// Tải Trí nhớ tổng dùng chung cho mọi truyện. Nếu chưa có, tạo mặc định với quy tắc lọc name.
    public func loadGlobalMemory() -> String {
        let url = globalMemoryURL
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        let defaultPrompt = Self.defaultGlobalMemoryPrompt
        saveGlobalMemory(defaultPrompt)
        return defaultPrompt
    }

    /// Lưu Trí nhớ tổng dùng chung cho mọi truyện.
    public func saveGlobalMemory(_ text: String) {
        let url = globalMemoryURL
        let data = Data(text.utf8)
        try? data.write(to: url, options: .atomic)
    }

    /// Khôi phục Trí nhớ tổng về chỉ dẫn mặc định.
    @discardableResult
    public func resetGlobalMemoryToDefault() -> String {
        let defaultPrompt = Self.defaultGlobalMemoryPrompt
        saveGlobalMemory(defaultPrompt)
        return defaultPrompt
    }
}
