import Foundation
import JavaScriptCore

/// Đuôi regex `##…` sau mã của `@js:` (spec §2.2 bước 3). `@js:` lấy mã tới hết chuỗi, nhưng nguồn hay viết
/// `@js:result.replace(…)##R##P` (晋江[网页] `@JSon:$..content@js:result.replace(…)##@无限好文…|…`): phần từ `##` là đuôi
/// regex áp lên kết quả JS (§2.6). Corpus: 86 khối `@js:` ở 65 nguồn chỉ phân tích được khi cắt tại `##` đầu tiên.
///
/// Chỉ tách khi chắc: có `##` nằm **ngoài** chuỗi/regex/template/chú thích JS, **cả** đoạn mã không phân tích được, còn phần
/// trước `##` thì phân tích được. Kiểm bằng `JSCheckScriptSyntax` — chỉ phân tích, không chạy — nên không có đoạn JS nào
/// chạy hai lần. Context kiểm cú pháp là context C riêng (không bootstrap, không `jsLib` của phiên); JavaScriptCore tự khoá
/// VM nên gọi được từ mọi thread engine. Quyết định theo văn bản mã nên được đệm.
enum LegadoJSRegexTail {
    struct Split {
        /// Mã JS trước `##`; có thể chỉ có khoảng trắng (`a.0@href@js:##R##P###` ⇒ không có phân đoạn JS).
        var code: String
        /// Từ `##` đầu tiên tới hết (đã trim): đánh giá như một lá `##R…` trên kết quả JS.
        var tail: String
    }

    /// `nil` = không tách (mã chạy nguyên như cũ).
    static func split(_ code: String) -> Split? {
        guard code.contains("##") else { return nil }
        let bytes = Array(code.utf8)
        lock.lock()
        let cached = decisions[code]
        lock.unlock()
        let position: Int
        if let cached {
            position = cached
        } else {
            position = decide(code, bytes: bytes)
            lock.lock()
            if decisions.count >= capacity { decisions.removeAll(keepingCapacity: true) }
            decisions[code] = position
            lock.unlock()
        }
        guard position >= 0 else { return nil }
        let tail = LegadoRuleScanner.string(bytes, position, bytes.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return Split(code: LegadoRuleScanner.string(bytes, 0, position), tail: tail)
    }

    // MARK: - Quyết định

    private static let lock = NSLock()
    /// Văn bản mã → vị trí byte của `##` để tách, `-1` = không tách.
    private static var decisions: [String: Int] = [:]
    private static let capacity = 512
    /// Context C chỉ để kiểm cú pháp, tạo lười dưới `lock`, sống cùng app.
    private static var syntaxContext: JSGlobalContextRef?

    private static func decide(_ code: String, bytes: [UInt8]) -> Int {
        guard let position = firstHashPair(in: bytes) else { return -1 }
        let prefix = LegadoRuleScanner.string(bytes, 0, position)
        lock.lock()
        defer { lock.unlock() }
        if syntaxContext == nil { syntaxContext = JSGlobalContextCreate(nil) }
        guard let context = syntaxContext else { return -1 }
        guard !parses(code, in: context), parses(prefix, in: context) else { return -1 }
        return position
    }

    /// Phân tích được như runtime chạy: script (eval gián tiếp), hoặc thân hàm khi có `return` ở cấp ngoài cùng
    /// (`returnWrapperHead` của `LegadoJSRuntime`). Placeholder `{{…}}` được thay trước khi chạy (§2.7) nên cũng thử bản
    /// đã thay mỗi `{{…}}` bằng `0`.
    private static func parses(_ code: String, in context: JSGlobalContextRef) -> Bool {
        if parsesAsScriptOrBody(code, in: context) { return true }
        guard code.contains("{{") else { return false }
        return parsesAsScriptOrBody(neutralizingPlaceholders(code), in: context)
    }

    private static func parsesAsScriptOrBody(_ code: String, in context: JSGlobalContextRef) -> Bool {
        checkSyntax(code, in: context) || checkSyntax("(function(){{" + code + "\n}})", in: context)
    }

    private static func checkSyntax(_ code: String, in context: JSGlobalContextRef) -> Bool {
        guard let script = JSStringCreateWithCFString(code as CFString) else { return false }
        defer { JSStringRelease(script) }
        return JSCheckScriptSyntax(context, script, nil, 1, nil)
    }

    private static func neutralizingPlaceholders(_ code: String) -> String {
        let bytes = Array(code.utf8)
        var output: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == LegadoRuleScanner.brace, index + 1 < bytes.count, bytes[index + 1] == LegadoRuleScanner.brace,
               let end = LegadoRuleScanner.balancedEnd(bytes, from: index) {
                output.append(UInt8(ascii: "0"))
                index = end
                continue
            }
            output.append(bytes[index])
            index += 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    // MARK: - Bộ quét từ vựng JS tối giản

    /// Vị trí của `##` đầu tiên ngoài chuỗi `'…'`/`"…"`, template `` `…` ``, regex `/…/`, chú thích và vùng `{{…}}`.
    /// Phân biệt regex với phép chia theo ký tự có nghĩa đứng trước (kiểu trình phân tích từ vựng JS); đoán sai chỉ làm lỡ
    /// một lần tách hoặc chọn một vị trí mà bước kiểm cú pháp sẽ loại.
    static func firstHashPair(in bytes: [UInt8]) -> Int? {
        var index = 0
        var previous = Previous.start
        while index < bytes.count {
            let byte = bytes[index]
            let next: UInt8 = index + 1 < bytes.count ? bytes[index + 1] : 0
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0B || byte == 0x0C {
                index += 1
                continue
            }
            if byte == hash, next == hash { return index }
            if byte == LegadoRuleScanner.brace, next == LegadoRuleScanner.brace,
               let end = LegadoRuleScanner.balancedEnd(bytes, from: index) {
                index = end
                previous = .value
                continue
            }
            if byte == LegadoRuleScanner.doubleQuote || byte == LegadoRuleScanner.singleQuote {
                index = endOfString(bytes, from: index)
                previous = .value
                continue
            }
            if byte == LegadoRuleScanner.backtick {
                index = endOfTemplate(bytes, from: index)
                previous = .value
                continue
            }
            if byte == slash {
                if next == slash {
                    index = endOfLine(bytes, from: index)
                    continue
                }
                if next == star {
                    index = endOfBlockComment(bytes, from: index)
                    continue
                }
                if previous.allowsRegex, let end = endOfRegex(bytes, from: index) {
                    index = end
                    previous = .value
                    continue
                }
                index += 1
                previous = .punctuation(slash)
                continue
            }
            if isWordByte(byte) {
                let start = index
                while index < bytes.count, isWordByte(bytes[index]) { index += 1 }
                previous = .word(LegadoRuleScanner.string(bytes, start, index))
                continue
            }
            previous = .punctuation(byte)
            index += 1
        }
        return nil
    }

    private enum Previous {
        case start
        /// Chuỗi, template, regex, vùng `{{…}}`.
        case value
        case word(String)
        case punctuation(UInt8)

        /// `/` mở regex (không phải phép chia) sau vị trí này.
        var allowsRegex: Bool {
            switch self {
            case .start: return true
            case .value: return false
            case .word(let word): return LegadoJSRegexTail.regexKeywords.contains(word)
            case .punctuation(let byte):
                return byte != LegadoRuleScanner.closeParen && byte != LegadoRuleScanner.closeSquare
            }
        }
    }

    private static let regexKeywords: Set<String> = [
        "return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "throw", "case", "do", "else",
        "yield", "await",
    ]

    /// Sau dấu nháy đóng; chuỗi không đóng dừng ở xuống dòng.
    private static func endOfString(_ bytes: [UInt8], from start: Int) -> Int {
        let quote = bytes[start]
        var index = start + 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == LegadoRuleScanner.backslash {
                index += 2
                continue
            }
            if byte == quote { return index + 1 }
            if byte == 0x0A { return index }
            index += 1
        }
        return bytes.count
    }

    /// Sau dấu `` ` `` đóng; `${…}` bên trong được quét lồng (chuỗi, template con, ngoặc nhọn).
    private static func endOfTemplate(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start + 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == LegadoRuleScanner.backslash {
                index += 2
                continue
            }
            if byte == LegadoRuleScanner.backtick { return index + 1 }
            if byte == LegadoRuleScanner.dollar, index + 1 < bytes.count, bytes[index + 1] == LegadoRuleScanner.brace {
                index = endOfTemplateExpression(bytes, from: index + 2)
                continue
            }
            index += 1
        }
        return bytes.count
    }

    private static func endOfTemplateExpression(_ bytes: [UInt8], from start: Int) -> Int {
        var depth = 1
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == LegadoRuleScanner.doubleQuote || byte == LegadoRuleScanner.singleQuote {
                index = endOfString(bytes, from: index)
                continue
            }
            if byte == LegadoRuleScanner.backtick {
                index = endOfTemplate(bytes, from: index)
                continue
            }
            if byte == LegadoRuleScanner.brace { depth += 1 }
            if byte == LegadoRuleScanner.closeBrace {
                depth -= 1
                if depth == 0 { return index + 1 }
            }
            index += 1
        }
        return bytes.count
    }

    private static func endOfLine(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0x0A { index += 1 }
        return index
    }

    private static func endOfBlockComment(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start + 2
        while index + 1 < bytes.count {
            if bytes[index] == star, bytes[index + 1] == slash { return index + 2 }
            index += 1
        }
        return bytes.count
    }

    /// Sau `/` đóng và cờ; regex không đóng trên cùng dòng ⇒ `nil` (coi `/` là phép chia).
    private static func endOfRegex(_ bytes: [UInt8], from start: Int) -> Int? {
        var index = start + 1
        var inClass = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x0A || byte == 0x0D { return nil }
            if byte == LegadoRuleScanner.backslash {
                index += 2
                continue
            }
            if inClass {
                if byte == LegadoRuleScanner.closeSquare { inClass = false }
            } else if byte == LegadoRuleScanner.openSquare {
                inClass = true
            } else if byte == slash {
                index += 1
                while index < bytes.count, isWordByte(bytes[index]) { index += 1 }
                return index
            }
            index += 1
        }
        return nil
    }

    /// Chữ của tên/số/từ khoá JS; byte ≥ 0x80 tính là chữ (nguồn đặt tên biến tiếng Hán: `类`, `小说`).
    private static func isWordByte(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
            || byte == 0x5F || byte == LegadoRuleScanner.dollar || byte >= 0x80
    }

    private static let hash = UInt8(ascii: "#")
    private static let slash = UInt8(ascii: "/")
    private static let star = UInt8(ascii: "*")
}
