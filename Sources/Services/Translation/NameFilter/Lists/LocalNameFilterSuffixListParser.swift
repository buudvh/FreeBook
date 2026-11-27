import Foundation

/// Dạng chữ của danh sách "Đuôi địa danh, tổ chức, thuật ngữ" (Lọc name local): mỗi dòng `chữ Hán=nghĩa|loại|vị trí`,
/// thêm `|off` ở cuối nếu đuôi **không dùng để dò** (cách A, 2026-11-27: đuôi vẫn ghép nghĩa, chỉ không vào bộ dò cố định
/// `LocalNameFilterSuffixStore.detectionSuffixes`); `loại` / `vị trí` là `rawValue` của `LocalNameFilter.SuffixKind`
/// (`place` / `sect` / `term`) và `LocalNameFilter.MeaningPosition` (`before` / `after`). Dòng trống và dòng bắt đầu bằng
/// `#` bỏ qua.
///
/// **Một** chỗ giữ luật khoá / nghĩa cho cả file gốc `NameFilterSuffixes.txt` lẫn sheet sửa (`keyError` /
/// `meaningError`) — sai ở đường nào cũng bị chặn như nhau. `isHanText` dùng chung cho danh sách "Không phải name".
enum LocalNameFilterSuffixListParser {
    typealias Value = LocalNameFilterSuffixEntry.Value

    struct Line: Equatable, Sendable {
        let key: String
        let value: Value
        /// `false` = dòng có `|off`: đuôi ghép nghĩa nhưng không vào bộ dò cố định (路 区 观 团 关 花 — dò ra rác).
        let isDetectable: Bool
    }

    struct Result: Sendable {
        /// Theo thứ tự trong file. Khoá lặp lại ⇒ giữ chỗ của lần đầu, nội dung lấy của dòng sau cùng.
        var lines: [Line] = []
        /// Dòng không phải ghi chú / dòng trống mà sai dạng hoặc sai luật.
        var invalidLineCount = 0
    }

    /// Đuôi dài tối đa 6 chữ (đếm code point) — việc 7 (2026-11-27, anh Bửu: "chọn đuôi thoải mái hơn"): danh sách chỉ để
    /// ghép nghĩa (cách A) nên đuôi dài không ảnh hưởng việc dò; bộ dò cố định (file gốc) vẫn chỉ dùng đuôi 1–2 chữ.
    static let maxKeyLength = 6
    static let notDetectedMarker = "off"

    static func parse(_ text: String) -> Result {
        var result = Result()
        var indexByKey: [String: Int] = [:]
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        // `\r\n` tách thành một dòng thật + một dòng rỗng — dòng rỗng bị bỏ qua như dòng trống.
        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let parsed = parseLine(line) else {
                result.invalidLineCount += 1
                continue
            }
            if let index = indexByKey[parsed.key] {
                result.lines[index] = parsed
            } else {
                indexByKey[parsed.key] = result.lines.count
                result.lines.append(parsed)
            }
        }
        return result
    }

    private static func parseLine(_ line: String) -> Line? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let key = line[..<separator].trimmingCharacters(in: .whitespaces)
        let fields = line[line.index(after: separator)...]
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 3 || fields.count == 4,
              let kind = LocalNameFilter.SuffixKind(rawValue: fields[1]),
              let position = LocalNameFilter.MeaningPosition(rawValue: fields[2]) else {
            return nil
        }
        var isDetectable = true
        if fields.count == 4 {
            guard fields[3] == notDetectedMarker else { return nil }
            isDetectable = false
        }
        let meaning = fields[0]
        guard keyError(key) == nil, meaningError(meaning) == nil else { return nil }
        return Line(key: key, value: Value(meaning: meaning, kind: kind, position: position), isDetectable: isDetectable)
    }

    /// Luật khoá: 1–6 chữ Hán. `nil` = hợp lệ.
    static func keyError(_ key: String) -> String? {
        if key.isEmpty { return "Chưa nhập đuôi." }
        guard key.unicodeScalars.count <= maxKeyLength, isHanText(key) else {
            return "Đuôi phải là 1 đến \(maxKeyLength) chữ Hán."
        }
        return nil
    }

    /// Luật nghĩa: không rỗng, không có `=`, `|` hay xuống dòng (làm vỡ dạng dòng của file). `nil` = hợp lệ.
    static func meaningError(_ meaning: String) -> String? {
        if meaning.isEmpty { return "Chưa nhập nghĩa." }
        if meaning.contains("=") || meaning.contains("|") || meaning.contains(where: \.isNewline) {
            return "Nghĩa không được có dấu =, | hay xuống dòng."
        }
        return nil
    }

    /// Chuỗi khác rỗng, mọi ký tự là chữ Hán — cùng dải với bộ lọc (`U+3400–4DBF`, `U+4E00–9FFF`, `U+F900–FAFF`) cộng
    /// khối mở rộng B (`U+20000–2A6DF`) như `VietPhraseTokenizer.isChineseCharacter`.
    static func isHanText(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF: return true
            default: return false
            }
        }
    }
}
