import Foundation

/// Dạng chữ của danh sách họ token `<ho>` (1.3.1062): mỗi dòng `chữ Hán=Âm`, dòng trống và dòng bắt đầu bằng `#` bỏ
/// qua. **Một** bộ đọc cho cả file gốc `ChineseSurnames.txt` lẫn file người dùng nhập, và cùng luật kiểm với sheet sửa
/// (`keyError` / `readingError`) — khoá hay âm sai ở đường nào cũng bị chặn như nhau.
enum QuickTranslationSurnameListParser {
    struct Line: Equatable, Sendable {
        let key: String
        let reading: String
    }

    struct Result: Sendable {
        /// Theo thứ tự trong file. Khoá lặp lại ⇒ giữ chỗ của lần đầu, âm lấy của dòng sau cùng.
        var lines: [Line] = []
        /// Dòng không phải ghi chú / dòng trống mà sai dạng `khoá=âm` hoặc sai luật khoá / âm.
        var invalidLineCount = 0
    }

    /// Parser ép `<ho>` về `1...2` đơn vị UTF-16 (`DictionaryKind.fixedLengthRange`): khoá dài hơn không bao giờ khớp,
    /// nên chặn ngay từ lúc nhập thay vì để nằm chết trong danh sách.
    static let maxKeyUTF16Length = 2

    static func parse(_ text: String) -> Result {
        var result = Result()
        var indexByKey: [String: Int] = [:]
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        // `\r\n` tách thành một dòng thật + một dòng rỗng — dòng rỗng bị bỏ qua như dòng trống.
        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else {
                result.invalidLineCount += 1
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let reading = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard keyError(key) == nil, readingError(reading) == nil else {
                result.invalidLineCount += 1
                continue
            }
            let parsed = Line(key: key, reading: reading)
            if let index = indexByKey[key] {
                result.lines[index] = parsed
            } else {
                indexByKey[key] = result.lines.count
                result.lines.append(parsed)
            }
        }
        return result
    }

    /// Luật khoá: 1 hoặc 2 chữ Hán, tổng độ dài UTF-16 ≤ 2. `nil` = hợp lệ.
    static func keyError(_ key: String) -> String? {
        if key.isEmpty { return "Chưa nhập họ." }
        guard key.utf16.count <= maxKeyUTF16Length,
              key.allSatisfy({ VietPhraseTokenizer.isChineseCharacter($0) }) else {
            return "Họ phải là 1 hoặc 2 chữ Hán."
        }
        return nil
    }

    /// Luật âm: không rỗng, không có `=` hay xuống dòng (sẽ làm vỡ dạng `khoá=âm` khi xuất). `nil` = hợp lệ.
    static func readingError(_ reading: String) -> String? {
        if reading.isEmpty { return "Chưa nhập âm đọc." }
        if reading.contains("=") || reading.contains(where: \.isNewline) {
            return "Âm đọc không được có dấu = hay xuống dòng."
        }
        return nil
    }

    /// File xuất: họ **đang bật** theo đúng thứ tự màn Danh sách họ, cùng dạng với file gốc (họ đang tắt bị bỏ, như cách
    /// `QuickTranslationRuleExporter` bỏ rule đang tắt).
    static func serialize(_ entries: [QuickTranslationSurnameEntry]) -> String {
        entries
            .filter(\.isEnabled)
            .map { "\($0.key)=\($0.reading)\n" }
            .joined()
    }
}
