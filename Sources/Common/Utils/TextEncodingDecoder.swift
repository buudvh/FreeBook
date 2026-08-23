import Foundation

/// Giải mã `Data` thành `String` bằng cách thử tuần tự nhiều bảng mã.
/// Thứ tự ưu tiên xem `TextEncodingOption.allCases`.
enum TextEncodingDecoder {
    /// Auto-detect: thử lần lượt theo `TextEncodingOption.allCases`, trả chuỗi
    /// đầu tiên giải mã thành công. Trả `""` nếu không có bảng mã nào khớp.
    static func decode(_ data: Data) -> String {
        for option in TextEncodingOption.allCases {
            if let text = option.decode(data) {
                return text
            }
        }
        return ""
    }

    /// Xác định bảng mã đầu tiên giải mã được `Data` (theo thứ tự ưu tiên).
    /// Dùng để đánh dấu bảng mã đang hoạt động với file TXT đang import.
    static func detect(_ data: Data) -> TextEncodingOption? {
        for option in TextEncodingOption.allCases {
            if option.decode(data) != nil {
                return option
            }
        }
        return nil
    }

    /// Giải mã bằng một bảng mã cụ thể (chọn thủ công).
    static func decode(_ data: Data, using option: TextEncodingOption) -> String? {
        return option.decode(data)
    }

    /// Ánh xạ tên bảng mã kiểu IANA (`<meta charset>`, `<?xml encoding=…?>`, codepage của MOBI)
    /// sang `TextEncodingOption`. Trả `nil` khi không có case tương ứng — caller rơi về auto-detect.
    static func option(forCharsetName name: String) -> TextEncodingOption? {
        let key = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()
        switch key {
        case "utf-8", "utf8", "utf_8", "65001":
            return .utf8
        case "utf-16", "utf-16le", "utf16le", "utf-16-le":
            return .utf16LE
        case "utf-16be", "utf16be", "utf-16-be":
            return .utf16BE
        case "utf-32", "utf-32le", "utf32le":
            return .utf32LE
        case "utf-32be", "utf32be":
            return .utf32BE
        case "gb2312", "gbk", "cp936", "ms936", "x-gbk":
            return .gbk
        case "gb18030":
            return .gb18030
        case "big5-hkscs", "big5hkscs", "hkscs":
            return .big5HKSCS
        case "big5", "cp950", "big-5", "big_5":
            return .big5
        case "euc-jp", "eucjp", "x-euc-jp":
            return .eucJP
        case "windows-1258", "cp1258":
            return .windowsVietnamese
        case "viscii":
            return .viscii
        case "iso-8859-1", "iso8859-1", "latin1", "iso_8859-1":
            return .isoLatin1
        case "windows-1250", "cp1250":
            return .windows1250
        case "windows-1251", "cp1251":
            return .windows1251
        case "windows-1252", "cp1252", "1252":
            return .windows1252
        case "windows-1253", "cp1253":
            return .windows1253
        case "windows-1254", "cp1254":
            return .windows1254
        case "us-ascii", "ascii":
            return .ascii
        default:
            return nil
        }
    }

    /// Giải mã theo bảng mã **file tự khai**. Trả `nil` khi không có khai báo, tên lạ hoặc
    /// giải mã thất bại — caller tự rơi về `decode(_:)` auto-detect.
    static func decodeDeclared(_ data: Data, charsetName: String?) -> String? {
        guard let charsetName, let option = option(forCharsetName: charsetName) else { return nil }
        return option.decode(data)
    }

    static func cfEncoding(_ cf: CFStringEncodings) -> String.Encoding {
        let rawValue = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue))
        return String.Encoding(rawValue: rawValue)
    }

    static func stripBOM(_ text: String?) -> String? {
        guard var text else { return nil }
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return text
    }
}