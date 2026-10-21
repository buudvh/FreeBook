import Foundation

/// Tách danh sách ảnh từ chuỗi HTML `content` của nguồn tranh (spec §8.2, §8.2.1). Hàm thuần, không mạng.
///
/// - Mỗi thẻ `<img …>` (không phân biệt hoa thường) là một trang ảnh, theo thứ tự xuất hiện. Ảnh trùng URL **giữ cả
///   hai** (tranh có thể lặp trang).
/// - Giá trị `src` đọc bằng **bộ tách khoan dung**: nguồn hay dựng `'<img src="' + url + ',' + JSON.stringify(opt) + '">'`,
///   tức dấu `"` của JSON nằm **bên trong** thuộc tính bọc bằng `"` — parser HTML chuẩn (kể cả SwiftSoup) cắt sai.
///   Gặp `,{` thì đọc trọn khối option (đếm ngoặc, bỏ qua chuỗi JSON) rồi mới tìm dấu nháy đóng.
/// - Ảnh lười: dùng `src`; **chỉ khi** `src` rỗng hoặc là ảnh giữ chỗ `data:` nhỏ (< 1 KB) mà thẻ có `data-original` /
///   `data-src` thì lấy thuộc tính đó.
/// - Không có thẻ `<img>` nào mà mọi dòng không rỗng đều là URL `http(s)` ⇒ mỗi dòng một ảnh.
enum LegadoComicImageExtractor {
    /// Một ảnh: phần URL (đã giải thực thể HTML, có thể còn tương đối) và khối option `{…}` nguyên văn (nếu có).
    struct RawImage: Equatable {
        let url: String
        let option: String?
    }

    /// Ảnh giữ chỗ `data:` nhỏ hơn mức này (ký tự) coi như "chưa có ảnh thật" (≈ 1 KB sau base64).
    static let placeholderDataLimit = 1400

    static func images(in html: String) -> [RawImage] {
        let bytes = Array(html.utf8)
        var output: [RawImage] = []
        var sawImageTag = false
        var index = 0
        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "<"), isImageTag(bytes, at: index) else {
                index += 1
                continue
            }
            sawImageTag = true
            let parsed = parseTag(bytes, from: index + 4)
            index = parsed.end
            if let image = chooseSource(parsed.attributes) {
                output.append(image)
            }
        }
        if !sawImageTag {
            return urlLines(in: html)
        }
        return output
    }

    // MARK: - Thẻ

    private static func isImageTag(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index + 4 <= bytes.count else { return false }
        let name = bytes[(index + 1)..<(index + 4)].map { $0 | 0x20 }
        guard name == Array("img".utf8) else { return false }
        guard index + 4 < bytes.count else { return true }
        let next = bytes[index + 4]
        return isSpace(next) || next == UInt8(ascii: "/") || next == UInt8(ascii: ">")
    }

    /// Đọc các thuộc tính tới `>`; tên thuộc tính chữ thường, giá trị thô (thuộc tính lặp: bản đầu thắng, như HTML).
    private static func parseTag(_ bytes: [UInt8], from start: Int) -> (attributes: [String: String], end: Int) {
        var attributes: [String: String] = [:]
        var index = start
        while index < bytes.count {
            while index < bytes.count, isSpace(bytes[index]) || bytes[index] == UInt8(ascii: "/") { index += 1 }
            guard index < bytes.count else { break }
            if bytes[index] == UInt8(ascii: ">") {
                index += 1
                break
            }
            let nameStart = index
            while index < bytes.count, !isSpace(bytes[index]), bytes[index] != UInt8(ascii: "="),
                  bytes[index] != UInt8(ascii: ">"), bytes[index] != UInt8(ascii: "/") {
                index += 1
            }
            let name = String(decoding: bytes[nameStart..<index], as: UTF8.self).lowercased()
            if name.isEmpty {
                index += 1
                continue
            }
            var probe = index
            while probe < bytes.count, isSpace(bytes[probe]) { probe += 1 }
            var value = ""
            if probe < bytes.count, bytes[probe] == UInt8(ascii: "=") {
                probe += 1
                while probe < bytes.count, isSpace(bytes[probe]) { probe += 1 }
                let read = name == "src" ? readSourceValue(bytes, from: probe) : readPlainValue(bytes, from: probe)
                value = read.value
                index = read.end
            }
            if attributes[name] == nil { attributes[name] = value }
        }
        return (attributes, index)
    }

    /// Giá trị thường: trong nháy (`"`/`'`) tới nháy đóng; không nháy thì tới khoảng trắng hoặc `>`.
    private static func readPlainValue(_ bytes: [UInt8], from start: Int) -> (value: String, end: Int) {
        guard start < bytes.count else { return ("", start) }
        let first = bytes[start]
        if first == UInt8(ascii: "\"") || first == UInt8(ascii: "'") {
            var index = start + 1
            while index < bytes.count, bytes[index] != first { index += 1 }
            let value = String(decoding: bytes[(start + 1)..<index], as: UTF8.self)
            return (value, min(index + 1, bytes.count))
        }
        var index = start
        while index < bytes.count, !isSpace(bytes[index]), bytes[index] != UInt8(ascii: ">") { index += 1 }
        return (String(decoding: bytes[start..<index], as: UTF8.self), index)
    }

    /// Bộ tách khoan dung của `src` (spec §8.2.1). Khối option không đóng ⇒ đọc lại như giá trị thường.
    private static func readSourceValue(_ bytes: [UInt8], from start: Int) -> (value: String, end: Int) {
        guard start < bytes.count else { return ("", start) }
        let first = bytes[start]
        let quote: UInt8? = (first == UInt8(ascii: "\"") || first == UInt8(ascii: "'")) ? first : nil
        var index = quote == nil ? start : start + 1
        let valueStart = index
        var depth = 0
        var stringQuote: UInt8?
        while index < bytes.count {
            let byte = bytes[index]
            if depth > 0 {
                if let open = stringQuote {
                    if byte == UInt8(ascii: "\\") {
                        index += 2
                        continue
                    }
                    if byte == open { stringQuote = nil }
                } else if byte == UInt8(ascii: "\"") || (byte == UInt8(ascii: "'") && quote != UInt8(ascii: "'")) {
                    stringQuote = byte
                } else if byte == UInt8(ascii: "{") {
                    depth += 1
                } else if byte == UInt8(ascii: "}") {
                    depth -= 1
                }
                index += 1
                continue
            }
            if byte == UInt8(ascii: ","), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "{") {
                depth = 1
                index += 2
                continue
            }
            if let quote {
                if byte == quote {
                    let value = String(decoding: bytes[valueStart..<index], as: UTF8.self)
                    return (value, index + 1)
                }
            } else if isSpace(byte) || byte == UInt8(ascii: ">") {
                return (String(decoding: bytes[valueStart..<index], as: UTF8.self), index)
            }
            index += 1
        }
        if depth > 0 {
            return readPlainValue(bytes, from: start)
        }
        return (String(decoding: bytes[valueStart..<min(index, bytes.count)], as: UTF8.self), bytes.count)
    }

    // MARK: - Chọn nguồn ảnh

    private static func chooseSource(_ attributes: [String: String]) -> RawImage? {
        let source = split(attributes["src"] ?? "")
        let trimmedURL = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholder = trimmedURL.isEmpty
            || (trimmedURL.lowercased().hasPrefix("data:") && trimmedURL.utf8.count < placeholderDataLimit)
        if isPlaceholder {
            for key in ["data-original", "data-src"] {
                let lazy = split(attributes[key] ?? "")
                if !lazy.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return lazy }
            }
        }
        return trimmedURL.isEmpty ? nil : source
    }

    /// `URL[,{option}]` → URL đã giải thực thể HTML (`&amp;` → `&`) + khối option giữ nguyên (chỉ giải `&quot;`).
    private static func split(_ raw: String) -> RawImage {
        let parts = LegadoURLResolver.splitOption(raw)
        let url = LegadoHTMLText.decodeEntities(parts.url).trimmingCharacters(in: .whitespacesAndNewlines)
        var option = parts.option
        if let text = option, text.contains("&quot;") {
            option = LegadoHTMLText.decodeEntities(text)
        }
        return RawImage(url: url, option: option)
    }

    /// Không có `<img>`: chuỗi gồm các dòng mà mỗi dòng không rỗng là một URL `http(s)` ⇒ mỗi dòng một ảnh.
    private static func urlLines(in text: String) -> [RawImage] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty, lines.allSatisfy({ LegadoURLResolver.hasHTTPScheme($0) && !$0.contains(" ") }) else {
            return []
        }
        return lines.map { split($0) }
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
    }
}
