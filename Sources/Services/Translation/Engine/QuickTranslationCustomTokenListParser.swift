import Foundation

/// Luật và dạng chữ của **token tùy chọn** `<@tên>` (1.3.1063) — **một** chỗ cho sheet thêm / sửa, nhập file, store và
/// parser rule, để khoá hay tên sai ở đường nào cũng bị chặn như nhau (khuôn `QuickTranslationSurnameListParser`).
///
/// File danh sách từ: mỗi dòng `chữ gốc=nghĩa`, dòng trống và dòng bắt đầu bằng `#` bỏ qua, cắt ở dấu `=` **đầu tiên**.
enum QuickTranslationCustomTokenListParser {
    typealias Entry = QuickTranslationCustomToken.Entry

    struct Result: Sendable {
        /// Theo thứ tự trong file. Khoá lặp lại ⇒ giữ chỗ của lần đầu, nghĩa lấy của dòng sau cùng.
        var entries: [Entry] = []
        /// Dòng không phải ghi chú / dòng trống mà sai dạng `khoá=nghĩa` hoặc sai luật khoá / nghĩa.
        var invalidLineCount = 0
    }

    static let maxNameLength = 20
    /// Trần độ dài chữ gốc = mặc định 1–12 của token từ điển (`<vp>`, `<ne>`): parser đặt `maxLength` của `<@tên>` bằng
    /// số này nên khoá dài hơn không bao giờ khớp — chặn ngay từ lúc nhập.
    static let maxKeyUTF16Length = 12

    // MARK: - Tên token

    /// `a-z`, `0-9`, `_`, bắt đầu bằng chữ, tối đa 20 ký tự. `nil` = hợp lệ.
    static func nameError(_ name: String) -> String? {
        if name.isEmpty { return "Chưa nhập tên token." }
        guard isValidName(name) else { return "Tên chỉ gồm a-z, 0-9, _ và bắt đầu bằng chữ." }
        if name.count > maxNameLength { return "Tên dài tối đa \(maxNameLength) ký tự." }
        return nil
    }

    private static let lowercaseLetters: ClosedRange<Unicode.Scalar> = "a"..."z"
    private static let digits: ClosedRange<Unicode.Scalar> = "0"..."9"

    static func isValidName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, lowercaseLetters.contains(first) else { return false }
        return name.unicodeScalars.allSatisfy { lowercaseLetters.contains($0) || digits.contains($0) || $0 == "_" }
    }

    /// Tên ghi trong rule (phần sau `@`): chữ thường hợp lệ ⇒ `(tên, false)`; bản viết HOA toàn bộ của một tên hợp lệ
    /// (`MAU`, `DV_2`) ⇒ `(tên thường, true)` = ép viết hoa nghĩa như `<VP>`. Còn lại (`Mau`, `màu`, rỗng) ⇒ `nil`.
    static func ruleName(_ raw: String) -> (name: String, capitalizesMeaning: Bool)? {
        if nameError(raw) == nil { return (raw, false) }
        let lowered = raw.lowercased()
        guard lowered != raw, raw == raw.uppercased(), nameError(lowered) == nil else { return nil }
        return (lowered, true)
    }

    // MARK: - Một từ

    /// Chữ gốc: không rỗng, ≤ 12 đơn vị UTF-16, không có `=` hay xuống dòng. `nil` = hợp lệ.
    static func keyError(_ key: String) -> String? {
        if key.isEmpty { return "Chưa nhập chữ gốc." }
        if key.contains("=") || key.contains(where: \.isNewline) {
            return "Chữ gốc không được có dấu = hay xuống dòng."
        }
        if key.utf16.count > maxKeyUTF16Length { return "Chữ gốc dài tối đa \(maxKeyUTF16Length) ký tự." }
        return nil
    }

    /// Nghĩa: không rỗng, không có xuống dòng (sẽ làm vỡ dạng `khoá=nghĩa` khi xuất). `nil` = hợp lệ.
    static func meaningError(_ meaning: String) -> String? {
        if meaning.isEmpty { return "Chưa nhập nghĩa." }
        if meaning.contains(where: \.isNewline) { return "Nghĩa không được xuống dòng." }
        return nil
    }

    // MARK: - File

    static func parse(_ text: String) -> Result {
        var result = Result()
        var indexByKey: [String: Int] = [:]
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else {
                result.invalidLineCount += 1
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let meaning = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard keyError(key) == nil, meaningError(meaning) == nil else {
                result.invalidLineCount += 1
                continue
            }
            let entry = Entry(key: key, meaning: meaning)
            if let index = indexByKey[key] {
                result.entries[index] = entry
            } else {
                indexByKey[key] = result.entries.count
                result.entries.append(entry)
            }
        }
        return result
    }

    /// File xuất: mọi từ theo đúng thứ tự màn danh sách, cùng dạng file nhập.
    static func serialize(_ entries: [Entry]) -> String {
        entries.map { "\($0.key)=\($0.meaning)\n" }.joined()
    }
}
