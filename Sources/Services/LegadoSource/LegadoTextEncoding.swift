import Foundation

/// Bảng mã cho phân hệ nguồn Legado.
///
/// `TextEncodingDecoder` của repo chỉ **giải mã**; ở đây còn cần **mã hoá** (percent-encode từ khoá
/// tìm kiếm sang GBK). Giữ bảng riêng thay vì mở rộng `TextEncodingOption` để không đẩy file đó vượt
/// baseline dòng của `check_architecture.py`, và đúng quy ước "mỗi owner tự cài" của repo.
public enum LegadoTextEncoding {

    public static func encoding(forCharsetName raw: String?) -> String.Encoding? {
        guard let raw else { return nil }
        let key = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()
        switch key {
        case "utf-8", "utf8", "utf_8":
            return .utf8
        case "gb2312", "gbk", "cp936", "ms936", "x-gbk", "euc-cn":
            return cfEncoding(.GBK_95)
        case "gb18030":
            return cfEncoding(.GB_18030_2000)
        case "big5", "cp950", "big-5", "big_5":
            return cfEncoding(.big5)
        case "big5-hkscs", "big5hkscs":
            return cfEncoding(.big5_HKSCS_1999)
        case "shift_jis", "shift-jis", "sjis":
            return .shiftJIS
        case "euc-jp", "eucjp":
            return .japaneseEUC
        case "iso-8859-1", "latin1", "iso8859-1":
            return .isoLatin1
        case "windows-1252", "cp1252":
            return .windowsCP1252
        default:
            return nil
        }
    }

    /// Giải mã phản hồi: ưu tiên bảng mã nguồn khai, sau đó `<meta charset>`, cuối cùng auto-detect.
    public static func decode(_ data: Data, declaredCharset: String?) -> String {
        if let encoding = encoding(forCharsetName: declaredCharset),
           let text = String(data: data, encoding: encoding), !text.isEmpty {
            return text
        }
        if let metaCharset = detectMetaCharset(data),
           let encoding = encoding(forCharsetName: metaCharset),
           let text = String(data: data, encoding: encoding), !text.isEmpty {
            return text
        }
        return TextEncodingDecoder.decode(data)
    }

    /// Đọc `<meta charset=…>` từ 2 KiB đầu — đủ vì thẻ meta phải nằm trong `<head>`.
    public static func detectMetaCharset(_ data: Data) -> String? {
        let head = data.prefix(2048)
        guard let ascii = String(data: head, encoding: .isoLatin1) else { return nil }
        let patterns = [
            #"charset\s*=\s*["']?([A-Za-z0-9_\-]+)"#,
            #"encoding\s*=\s*["']?([A-Za-z0-9_\-]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(location: 0, length: (ascii as NSString).length)
            guard let match = regex.firstMatch(in: ascii, options: [], range: range),
                  match.numberOfRanges > 1 else { continue }
            let captured = (ascii as NSString).substring(with: match.range(at: 1))
            if !captured.isEmpty { return captured }
        }
        return nil
    }

    private static func cfEncoding(_ value: CFStringEncodings) -> String.Encoding {
        let rawValue = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(value.rawValue))
        return String.Encoding(rawValue: rawValue)
    }
}
