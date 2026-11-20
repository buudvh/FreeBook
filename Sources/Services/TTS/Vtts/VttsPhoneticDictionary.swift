import Foundation

/// Từ điển phiên âm **riêng của vtts** (khoá = từ gốc, giá trị = cách đọc tiếng Việt) — 1.3.1041, anh Bửu: "thêm từ điển
/// phiên âm giống vieneu và pipertts". Độc lập với từ điển NghiTTS (`TextPreprocessor`) và VieNeu
/// (`VieNeuJapaneseDictionary`): sửa bên này không đổi cách đọc bên kia.
///
/// ## Khoá: hạ chữ thường, **giữ dấu**
/// Khác VieNeu / NghiTTS (gấp dấu phụ): lúc đọc vtts tra **mọi** token của đoạn, kể cả chữ Việt có dấu, nên gấp dấu thì
/// mục "ban" sẽ thay luôn "bàn", "bán". Giữ dấu ⇒ mục chỉ khớp đúng chữ đã gõ (không phân biệt hoa thường). Chỗ tra / xoá
/// của sheet thêm từ dùng `normalizedKey` của type này, không dùng khoá gấp dấu của hai từ điển kia.
///
/// File `FreeBook/TTS/phien-am-vtts.plist` (cùng thư mục hai từ điển kia ⇒ màn Dung lượng tự đếm, sao lưu qua
/// `BackupPaths.ttsDictionaryFiles`).
actor VttsPhoneticDictionary {
    static let shared = VttsPhoneticDictionary()

    static let fileName = "phien-am-vtts.plist"
    /// Công tắc "Áp dụng từ điển phiên âm vtts" — chưa có khoá ⇒ **bật** (từ điển chỉ chứa mục người dùng tự thêm).
    static let enabledKey = "vttsDictionaryEnabled"

    private var words: [String: String] = [:]

    private init() {
        words = Self.loadFromDisk()
    }

    /// Đọc `UserDefaults` thuần — gọi được ở mọi thread.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    // MARK: - Tra cứu

    /// Khoá chuẩn hoá giống đường tra lúc đọc: bỏ khoảng trắng hai đầu, NFC, hạ chữ thường. **Không** gấp dấu.
    static func normalizedKey(_ word: String) -> String {
        word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    func lookup(_ word: String) -> String? {
        words[Self.normalizedKey(word)]
    }

    /// Cả bảng — tầng gọi tra nhiều token mà chỉ tốn một lượt nhảy actor.
    func all() -> [String: String] {
        words
    }

    // MARK: - Sửa

    func update(key: String, value: String) throws {
        let normalized = Self.normalizedKey(key)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !trimmed.isEmpty else { return }
        words[normalized] = trimmed
        try saveToDisk()
    }

    func delete(key: String) throws {
        words.removeValue(forKey: Self.normalizedKey(key))
        try saveToDisk()
    }

    func deleteAll() throws {
        words.removeAll()
        try saveToDisk()
    }

    /// Thay **cả bảng** rồi ghi một lần (nhập từ file). Khoá được chuẩn hoá lại, mục rỗng bị bỏ.
    func replaceAll(_ newWords: [String: String]) throws {
        var normalized: [String: String] = [:]
        for (key, value) in newWords {
            let normalizedKey = Self.normalizedKey(key)
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !trimmed.isEmpty else { continue }
            normalized[normalizedKey] = trimmed
        }
        words = normalized
        try saveToDisk()
    }

    /// Đọc lại từ đĩa — sau khi khôi phục bản sao lưu ghi đè file.
    func loadResources() {
        words = Self.loadFromDisk()
    }

    // MARK: - Đĩa

    static func fileURL() -> URL? {
        (try? ModelStore())?.rootURL.appendingPathComponent(fileName)
    }

    private static func loadFromDisk() -> [String: String] {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return [:] }
        return ((try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: String]) ?? [:]
    }

    private func saveToDisk() throws {
        guard let url = Self.fileURL() else {
            throw NSError(
                domain: "VttsPhoneticDictionary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Không định vị được thư mục FreeBook/TTS."]
            )
        }
        let data = try PropertyListSerialization.data(fromPropertyList: words, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
        AppLogger.shared.log("🗣️ [VttsPhoneticDictionary] Lưu \(words.count) mục vào \(url.lastPathComponent)")
    }
}
