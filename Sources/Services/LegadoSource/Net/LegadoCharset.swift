import Foundation

/// Tên bảng mã của nguồn Legado → `String.Encoding` (spec §3.8, §4.5, `java.strToBytes`).
///
/// Nhận cả tên IANA (`gbk`, `utf-8`) lẫn tên kiểu Java (`ISO8859_1`, `UTF_8`). `gbk`/`gb2312` dùng GB18030 (siêu tập,
/// mã hoá/giải mã được đủ ký tự).
enum LegadoCharset {
    static let gb18030 = encoding(cf: .GB_18030_2000)

    /// `nil` khi tên rỗng hoặc không nhận ra.
    static func encoding(named rawName: String?) -> String.Encoding? {
        guard let rawName else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        guard !name.isEmpty else { return nil }
        switch name {
        case "utf-8", "utf8": return .utf8
        case "gbk", "gb2312", "gb-2312", "x-gbk", "cp936", "ms936", "gb18030", "euc-cn", "euccn": return gb18030
        case "big5", "big-5", "cp950": return encoding(cf: .big5)
        case "big5-hkscs": return encoding(cf: .big5_HKSCS_1999)
        case "iso-8859-1", "iso8859-1", "latin1", "iso-8859-1:1987": return .isoLatin1
        case "us-ascii", "ascii": return .ascii
        case "utf-16", "utf16": return .utf16
        case "utf-16le": return .utf16LittleEndian
        case "utf-16be": return .utf16BigEndian
        case "shift-jis", "shift_jis", "sjis": return .shiftJIS
        case "euc-jp": return .japaneseEUC
        default:
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard cfEncoding != CFStringEncoding(0xFFFF_FFFF) else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        }
    }

    /// Bảng mã để **mã hoá request**: option `charset` (không có/không nhận ra ⇒ UTF-8).
    static func requestEncoding(named name: String?) -> String.Encoding {
        encoding(named: name) ?? .utf8
    }

    private static func encoding(cf: CFStringEncodings) -> String.Encoding {
        let rawValue = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue))
        return String.Encoding(rawValue: rawValue)
    }

    /// Byte của chuỗi theo bảng mã; ký tự không mã hoá được rơi về UTF-8 của ký tự đó.
    static func bytes(of text: String, encoding: String.Encoding) -> [UInt8] {
        if let data = text.data(using: encoding, allowLossyConversion: false) {
            return Array(data)
        }
        var output: [UInt8] = []
        for character in text {
            let piece = String(character)
            if let data = piece.data(using: encoding, allowLossyConversion: false) {
                output.append(contentsOf: data)
            } else {
                output.append(contentsOf: Array(piece.utf8))
            }
        }
        return output
    }

    /// Chuỗi từ byte theo bảng mã; giải không được thì thử UTF-8 rồi tự dò (`TextEncodingDecoder`).
    static func string(from data: Data, encoding: String.Encoding?) -> String {
        if let encoding, let text = String(data: data, encoding: encoding) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        return TextEncodingDecoder.decode(data)
    }
}
