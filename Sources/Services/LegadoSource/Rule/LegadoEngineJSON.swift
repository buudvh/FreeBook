import Foundation

/// Giá trị JSON của engine nguồn Legado.
///
/// Không dùng `JSONSerialization` vì nó trả `NSDictionary` mất thứ tự khoá, trong khi `$.*`, `..` và việc in lại
/// object (spec §2.11.3) cần đúng thứ tự tài liệu. Số giữ cả văn bản gốc để in lại không thành `12.0`
/// hay dạng mũ, và để mã số dài (ID 19 chữ số) không mất chính xác.
enum LegadoEngineJSON {
    case null
    case bool(Bool)
    /// Giá trị số + văn bản gốc (rỗng khi số được dựng trong code).
    case number(Double, String)
    case string(String)
    case array([LegadoEngineJSON])
    case object([(key: String, value: LegadoEngineJSON)])

    // MARK: - Truy cập

    /// Giá trị của khoá trong object (bản xuất hiện **cuối** thắng, như JSON thường). `nil` nếu không phải object
    /// hoặc không có khoá.
    subscript(key: String) -> LegadoEngineJSON? {
        guard case .object(let entries) = self else { return nil }
        var found: LegadoEngineJSON?
        for entry in entries where entry.key == key {
            found = entry.value
        }
        return found
    }

    var arrayValue: [LegadoEngineJSON]? {
        if case .array(let items) = self { return items }
        return nil
    }

    var objectEntries: [(key: String, value: LegadoEngineJSON)]? {
        if case .object(let entries) = self { return entries }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var isContainer: Bool {
        switch self {
        case .array, .object: return true
        default: return false
        }
    }

    /// Chuỗi nếu là `.string`, `nil` với kiểu khác.
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Giá trị số (số thật hoặc chuỗi số); `nil` nếu không chuyển được.
    var doubleValue: Double? {
        switch self {
        case .number(let value, _): return value
        case .string(let text): return Double(text.trimmingCharacters(in: .whitespaces))
        case .bool(let flag): return flag ? 1 : 0
        default: return nil
        }
    }

    // MARK: - Chuyển chuỗi (spec §2.11.3)

    /// Chuỗi kết quả của `getString` cho một giá trị: chuỗi giữ nguyên, số thập phân gọn, bool `true`/`false`,
    /// `null` rỗng, object/mảng thành văn bản JSON gọn.
    var scalarString: String {
        switch self {
        case .null: return ""
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let value, let raw): return Self.formatNumber(value, raw: raw)
        case .string(let text): return text
        case .array, .object: return compactText
        }
    }

    /// Văn bản JSON gọn (không khoảng trắng thừa), giữ thứ tự khoá.
    var compactText: String {
        var output = ""
        Self.write(self, into: &output)
        return output
    }

    static func fromNumber(_ value: Double) -> LegadoEngineJSON {
        .number(value, "")
    }

    static func strings(_ values: [String]) -> LegadoEngineJSON {
        .array(values.map { LegadoEngineJSON.string($0) })
    }

    /// Số nguyên in không có `.0`, không dạng mũ; số nguyên dài giữ đúng văn bản gốc.
    static func formatNumber(_ value: Double, raw: String) -> String {
        if !raw.isEmpty, Self.isPlainInteger(raw) {
            return raw
        }
        if value.isFinite, value == value.rounded(), abs(value) < 9.0e18 {
            return String(Int64(value))
        }
        if !value.isFinite { return value.isNaN ? "NaN" : (value > 0 ? "Infinity" : "-Infinity") }
        return "\(value)"
    }

    private static func isPlainInteger(_ raw: String) -> Bool {
        var sawDigit = false
        for (offset, scalar) in raw.unicodeScalars.enumerated() {
            if scalar == "-" && offset == 0 { continue }
            guard scalar.value >= 48 && scalar.value <= 57 else { return false }
            sawDigit = true
        }
        return sawDigit
    }

    // MARK: - Tuần tự hoá

    private static func write(_ value: LegadoEngineJSON, into output: inout String) {
        switch value {
        case .null:
            output += "null"
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .number(let number, let raw):
            output += formatNumber(number, raw: raw)
        case .string(let text):
            writeString(text, into: &output)
        case .array(let items):
            output += "["
            for (index, item) in items.enumerated() {
                if index > 0 { output += "," }
                write(item, into: &output)
            }
            output += "]"
        case .object(let entries):
            output += "{"
            for (index, entry) in entries.enumerated() {
                if index > 0 { output += "," }
                writeString(entry.key, into: &output)
                output += ":"
                write(entry.value, into: &output)
            }
            output += "}"
        }
    }

    /// Chuỗi JSON có nháy kép; chỉ thoát ký tự bắt buộc, giữ nguyên ký tự không phải ASCII.
    static func quoted(_ text: String) -> String {
        var output = ""
        writeString(text, into: &output)
        return output
    }

    private static func writeString(_ text: String, into output: inout String) {
        output += "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case "\u{2028}": output += "\\u2028"
            case "\u{2029}": output += "\\u2029"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        output += "\""
    }
}
