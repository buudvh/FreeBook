import Foundation

/// Từ điển phiên âm **riêng cho VieNeu-TTS** (khoá = từ gốc, giá trị = cách đọc tiếng Việt).
///
/// ## Vì sao là type riêng chứ không dùng `TextPreprocessor.wordMap`
/// Hai lý do, cả hai đều cứng:
/// 1. **Độc lập hoàn toàn** (người dùng chốt 2026-10-01): VieNeu không rơi về từ điển của NghiTTS và
///    ngược lại, nên sửa bên này không bao giờ làm đổi cách đọc bên kia.
/// 2. `TextPreprocessor.swift` đang ở **1120/1121 dòng** — trần cứng của `check_architecture.py` — nên
///    **không** thêm được stored property nào vào đó.
///
/// ## Khoá **phải** ở dạng đã gấp dấu phụ
/// Lúc đọc, token được tra bằng khoá đã `folding(.diacriticInsensitive).lowercased()` (đúng cách
/// `TextPreprocessor.swift:982` làm cho từ điển NghiTTS). Khoá còn macron (`otōto`, `ōja`) là **mục
/// chết** vì không bao giờ khớp — vì vậy bước dựng file trên HuggingFace phải gấp macron trước.
public actor VieNeuJapaneseDictionary {
    public static let shared = VieNeuJapaneseDictionary()

    /// Tên file trong `FreeBook/TTS/` — **trùng** tên trên HuggingFace để một cái tên là đủ.
    public static let fileName = "phien-am-tieng-nhat.plist"

    private var words: [String: String] = [:]

    private init() {
        words = Self.loadFromDisk()
    }

    // MARK: - Tra cứu

    /// Khoá chuẩn hoá **giống hệt** đường tra lúc đọc: gấp dấu phụ rồi hạ chữ thường.
    public static func normalizedKey(_ word: String) -> String {
        word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .lowercased()
    }

    public func lookup(_ word: String) -> String? {
        words[Self.normalizedKey(word)]
    }

    /// Cả bảng, để tầng gọi tra nhiều token mà **chỉ** tốn một lượt nhảy actor.
    public func all() -> [String: String] {
        words
    }

    public func isEmpty() -> Bool {
        words.isEmpty
    }

    // MARK: - Sửa

    public func update(key: String, value: String) throws {
        let normalized = Self.normalizedKey(key)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !trimmed.isEmpty else { return }
        words[normalized] = trimmed
        try saveToDisk()
    }

    public func delete(key: String) throws {
        words.removeValue(forKey: Self.normalizedKey(key))
        try saveToDisk()
    }

    public func deleteAll() throws {
        words.removeAll()
        try saveToDisk()
    }

    /// Thay **cả bảng** rồi ghi một lần — dùng cho nhập từ file và cho lượt trộn sau khi tải.
    public func replaceAll(_ newWords: [String: String]) throws {
        words = newWords
        try saveToDisk()
    }

    public func loadResources() {
        words = Self.loadFromDisk()
    }

    // MARK: - Đĩa

    /// `FreeBook/TTS/phien-am-tieng-nhat.plist` — cùng thư mục với từ điển của NghiTTS.
    public static func fileURL() -> URL? {
        (try? ModelStore())?.rootURL.appendingPathComponent(fileName)
    }

    public static func existsOnDisk() -> Bool {
        guard let url = fileURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func loadFromDisk() -> [String: String] {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return [:] }
        return ((try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: String]) ?? [:]
    }

    private func saveToDisk() throws {
        guard let url = Self.fileURL() else {
            throw NSError(
                domain: "VieNeuJapaneseDictionary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Không định vị được thư mục FreeBook/TTS."]
            )
        }
        let data = try PropertyListSerialization.data(fromPropertyList: words, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
        AppLogger.shared.log("🗾 [VieNeuJapaneseDictionary] Lưu \(words.count) mục vào \(url.lastPathComponent)")
    }
}
