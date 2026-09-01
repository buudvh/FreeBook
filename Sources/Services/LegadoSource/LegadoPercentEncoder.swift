import Foundation

/// Percent-encode theo **bảng mã của nguồn**, không phải luôn UTF-8.
///
/// Web truyện Trung Quốc thường dùng GBK: từ khoá tìm kiếm phải thành `%CE%D2` chứ không phải
/// `%E6%88%91`. `AnalyzeUrl.encodeParams` (`:302`) làm đúng việc này; nếu bỏ qua thì tìm kiếm trả về
/// rỗng mà không có lỗi nào.
public enum LegadoPercentEncoder {

    /// Ký tự **không** bị encode (theo `application/x-www-form-urlencoded`).
    private static let unreserved: Set<UInt8> = {
        var set = Set<UInt8>()
        for scalar in UInt8(ascii: "a")...UInt8(ascii: "z") { set.insert(scalar) }
        for scalar in UInt8(ascii: "A")...UInt8(ascii: "Z") { set.insert(scalar) }
        for scalar in UInt8(ascii: "0")...UInt8(ascii: "9") { set.insert(scalar) }
        for character in "-_.*" { set.insert(character.asciiValue ?? 0) }
        return set
    }()

    public static func encode(_ text: String, charset: String?) -> String {
        guard let data = encodeToData(text, charset: charset) else { return text }
        var output = ""
        output.reserveCapacity(data.count * 3)
        for byte in data {
            if unreserved.contains(byte) {
                output.append(Character(UnicodeScalar(byte)))
            } else if byte == UInt8(ascii: " ") {
                output.append("+")
            } else {
                output.append(String(format: "%%%02X", byte))
            }
        }
        return output
    }

    /// Chuỗi → bytes theo bảng mã khai báo; `nil` charset ⇒ UTF-8.
    public static func encodeToData(_ text: String, charset: String?) -> Data? {
        guard let encoding = LegadoTextEncoding.encoding(forCharsetName: charset) else {
            return text.data(using: .utf8)
        }
        if let data = text.data(using: encoding) { return data }
        return text.data(using: .utf8)
    }

    /// Encode một chuỗi tham số `a=1&b=2`: chỉ encode **giá trị và khoá**, giữ `&` và `=`.
    ///
    /// Bỏ qua phần đã được encode sẵn (chuỗi chứa `%` theo sau hai chữ số hex) để không encode kép —
    /// `AnalyzeUrl.encodeParams` cũng kiểm tra điều này.
    public static func encodeQueryString(_ query: String, charset: String?) -> String {
        query.components(separatedBy: "&").map { pair -> String in
            guard let separator = pair.firstIndex(of: "=") else {
                return encodeIfNeeded(pair, charset: charset)
            }
            let key = String(pair[pair.startIndex..<separator])
            let value = String(pair[pair.index(after: separator)...])
            return encodeIfNeeded(key, charset: charset) + "=" + encodeIfNeeded(value, charset: charset)
        }
        .joined(separator: "&")
    }

    private static func encodeIfNeeded(_ text: String, charset: String?) -> String {
        if isAlreadyEncoded(text) { return text }
        return encode(text, charset: charset)
    }

    public static func isAlreadyEncoded(_ text: String) -> Bool {
        guard text.contains("%") else { return false }
        return text.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil
    }
}
