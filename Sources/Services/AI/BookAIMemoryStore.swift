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
    Khi tôi yêu cầu “lọc tên riêng” hoặc các câu có ý nghĩa tương tự như “lọc name”, “tìm tên”, “trích xuất tên”, “lấy tên riêng”, “lọc thực thể tên”, “extract name”…

    - Chỉ trả về kết quả, không Markdown, không giải thích, không thêm nội dung trước hoặc sau.
    - Mỗi tên một dòng theo format:
    Tên gốc=Nghĩa
    - Nếu không có tên riêng, trả về:
    Không có name

    Quy tắc:
    - Tên Trung Quốc → Hán Việt.
    - Tên Nhật, Hàn, Anh hoặc tên ngoại quốc viết bằng chữ Hán → phiên âm/cách viết đúng theo ngôn ngữ gốc, không đọc Hán Việt máy móc.
    - “Họ/Tên + đại từ nhân xưng/chức danh/cách gọi” → giữ đúng thứ tự “Họ/Tên + cách gọi tiếng Việt”.
    - Ví dụ:
    何老三=Hà lão tam
    李掌柜=Lý chưởng quầy
    李医生=Lý bác sĩ
    陈教授=Trần giáo sư
    王老板=Vương lão bản
    - Không đảo thành “bác sĩ Lý”, “giáo sư Trần”…
    """

    private var globalMemoryURL: URL {
        storageDirectory.appendingPathComponent("global_memory.txt")
    }

    /// Tải Trí nhớ tổng dùng chung cho mọi truyện. Nếu chưa có hoặc còn dùng prompt JSON cũ, tạo mặc định với quy tắc lọc name.
    public func loadGlobalMemory() -> String {
        let url = globalMemoryURL
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            if text.contains("JSON array") || text.contains("“original”") || text.contains("\"original\"") {
                let defaultPrompt = Self.defaultGlobalMemoryPrompt
                saveGlobalMemory(defaultPrompt)
                return defaultPrompt
            }
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
