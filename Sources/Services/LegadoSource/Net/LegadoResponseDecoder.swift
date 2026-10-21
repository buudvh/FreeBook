import Foundation

/// Giải mã thân phản hồi (spec §4.5, U7): `charset` trong `Content-Type` → option `charset` → BOM → `<meta charset>` /
/// `<meta http-equiv>` trong 2 KB đầu → UTF-8 → GB18030 → tự dò (`TextEncodingDecoder`).
enum LegadoResponseDecoder {
    private static let metaCharset = try? NSRegularExpression(
        pattern: "<meta[^>]+charset\\s*=\\s*[\"']?\\s*([A-Za-z0-9_\\-]+)", options: [.caseInsensitive]
    )

    static func decode(_ data: Data, contentType: String?, declaredCharset: String?) -> String {
        guard !data.isEmpty else { return "" }
        if let name = charset(fromContentType: contentType), let text = decode(data, charsetName: name) {
            return text
        }
        if let declaredCharset, let text = decode(data, charsetName: declaredCharset) {
            return text
        }
        if let text = decodeBOM(data) { return text }
        if let name = metaCharsetName(in: data), let text = decode(data, charsetName: name) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: LegadoCharset.gb18030) { return text }
        return TextEncodingDecoder.decode(data)
    }

    private static func decode(_ data: Data, charsetName: String) -> String? {
        guard let encoding = LegadoCharset.encoding(named: charsetName) else { return nil }
        guard var text = String(data: data, encoding: encoding) else { return nil }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    static func charset(fromContentType contentType: String?) -> String? {
        guard let contentType else { return nil }
        for part in contentType.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("charset=") else { continue }
            let value = String(trimmed.dropFirst("charset=".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func decodeBOM(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        return nil
    }

    private static func metaCharsetName(in data: Data) -> String? {
        guard let regex = metaCharset else { return nil }
        let head = String(decoding: data.prefix(2048), as: UTF8.self)
        let range = NSRange(head.startIndex..., in: head)
        guard let match = regex.firstMatch(in: head, range: range),
              let nameRange = Range(match.range(at: 1), in: head) else { return nil }
        return String(head[nameRange])
    }
}
