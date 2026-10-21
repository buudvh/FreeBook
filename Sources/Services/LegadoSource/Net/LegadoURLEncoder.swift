import Foundation

/// Mã hoá phần trăm URL và thân form theo bảng mã của nguồn (spec §3.8, `java.encodeURI` §6.4.3).
///
/// - Path: ký tự không phải ASCII → UTF-8 `%XX`; ASCII không hợp lệ trong URL (dấu cách, `"`, `<`, `>`, `{`, `|`…) cũng mã hoá.
/// - Query: tách `&`, mỗi phần tách tên/giá trị ở `=` đầu tiên; giữ `%XX` hợp lệ đã có, giữ ký tự an toàn, còn lại mã hoá
///   **theo bảng mã của nguồn**; dấu cách → `%20`.
/// - Form: như query nhưng dấu cách → `+`.
enum LegadoURLEncoder {
    /// Ký tự giữ nguyên trong giá trị query/form (ngoài chữ số và chữ cái ASCII).
    private static let queryKeep: Set<UInt8> = Set(Array("-_.~,:/@!$'()*+;=?".utf8))
    /// Ký tự ASCII giữ nguyên trong path.
    private static let pathKeep: Set<UInt8> = Set(Array("-_.~!$&'()*+,;=:@/%".utf8))
    /// Ký tự giữ nguyên cho `java.encodeURI` (gần `URLEncoder` của Java, dấu cách → `%20`).
    private static let componentKeep: Set<UInt8> = Set(Array("-_.*~".utf8))

    /// URL tuyệt đối (hoặc tương đối) → chuỗi ASCII gửi được. Fragment bị bỏ (không gửi lên mạng).
    static func encodeURL(_ url: String, encoding: String.Encoding) -> String {
        var text = url
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        var prefix = ""
        if let separator = text.range(of: "://") {
            let afterScheme = text[separator.upperBound...]
            let authorityEnd = afterScheme.firstIndex(where: { $0 == "/" || $0 == "?" }) ?? afterScheme.endIndex
            prefix = String(text[..<authorityEnd])
            text = String(text[authorityEnd...])
        }
        let path: String
        let query: String?
        if let question = text.firstIndex(of: "?") {
            path = String(text[..<question])
            query = String(text[text.index(after: question)...])
        } else {
            path = text
            query = nil
        }
        var output = prefix + encode(path, encoding: .utf8, keep: pathKeep, spaceAsPlus: false)
        if let query {
            output += "?" + encodeQuery(query, encoding: encoding, spaceAsPlus: false)
        }
        return output
    }

    /// Thân `application/x-www-form-urlencoded`.
    static func encodeForm(_ body: String, encoding: String.Encoding) -> String {
        encodeQuery(body, encoding: encoding, spaceAsPlus: true)
    }

    /// `java.encodeURI(s, enc)`: mã hoá **mọi** ký tự trừ chữ/số ASCII và `-_.*~`; dấu cách `%20` (U25).
    static func encodeComponent(_ text: String, encoding: String.Encoding) -> String {
        encode(text, encoding: encoding, keep: componentKeep, spaceAsPlus: false, keepExistingEscapes: false)
    }

    private static func encodeQuery(_ query: String, encoding: String.Encoding, spaceAsPlus: Bool) -> String {
        query.components(separatedBy: "&").map { pair -> String in
            guard let equals = pair.firstIndex(of: "=") else {
                return encode(pair, encoding: encoding, keep: queryKeep, spaceAsPlus: spaceAsPlus)
            }
            let name = String(pair[..<equals])
            let value = String(pair[pair.index(after: equals)...])
            return encode(name, encoding: encoding, keep: queryKeep, spaceAsPlus: spaceAsPlus) + "="
                + encode(value, encoding: encoding, keep: queryKeep, spaceAsPlus: spaceAsPlus)
        }.joined(separator: "&")
    }

    private static let hexDigits = Array("0123456789ABCDEF".utf8)

    private static func encode(_ text: String, encoding: String.Encoding, keep: Set<UInt8>,
                               spaceAsPlus: Bool, keepExistingEscapes: Bool = true) -> String {
        var output: [UInt8] = []
        output.reserveCapacity(text.utf8.count)
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if keepExistingEscapes, character == "%", index + 2 < characters.count,
               characters[index + 1].isHexDigit, characters[index + 2].isHexDigit {
                output.append(contentsOf: Array(String(characters[index...(index + 2)]).utf8))
                index += 3
                continue
            }
            if character == " " {
                output.append(contentsOf: spaceAsPlus ? [UInt8(ascii: "+")] : Array("%20".utf8))
                index += 1
                continue
            }
            if let ascii = character.asciiValue, isUnreserved(ascii) || keep.contains(ascii) {
                output.append(ascii)
                index += 1
                continue
            }
            for byte in LegadoCharset.bytes(of: String(character), encoding: encoding) {
                output.append(UInt8(ascii: "%"))
                output.append(hexDigits[Int(byte >> 4)])
                output.append(hexDigits[Int(byte & 0x0F)])
            }
            index += 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
    }
}
