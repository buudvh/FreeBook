import Foundation

/// Giải mã `Data` thành `String` bằng cách thử tuần tự nhiều bảng mã.
/// Thứ tự ưu tiên: UTF-8/BOM trước, kế tiếp là các mã đa byte (CJK) vì chúng
/// fail khi gặp chuỗi byte không hợp lệ, cuối cùng là mã đơn byte (thường không
/// bao giờ fail) để tránh nuốt nhầm file tiếng Trung thành Latin-1/CP125x.
enum TextEncodingDecoder {
    static func decode(_ data: Data) -> String {
        if let utf8Str = String(data: data, encoding: .utf8) {
            return utf8Str
        }

        if let utf16LE = stripBOM(String(data: data, encoding: .utf16LittleEndian)) {
            return utf16LE
        }
        if let utf16BE = stripBOM(String(data: data, encoding: .utf16BigEndian)) {
            return utf16BE
        }
        if let utf32LE = stripBOM(String(data: data, encoding: .utf32LittleEndian)) {
            return utf32LE
        }
        if let utf32BOM = stripBOM(String(data: data, encoding: .utf32)) {
            return utf32BOM
        }
        if let utf32BE = stripBOM(String(data: data, encoding: .utf32BigEndian)) {
            return utf32BE
        }

        if let gb18030 = String(data: data, encoding: cfEncoding(.GB_18030_2000)) {
            return gb18030
        }
        if let gbk = String(data: data, encoding: cfEncoding(.GBK_95)) {
            return gbk
        }
        if let big5HKSCS = String(data: data, encoding: cfEncoding(.big5_HKSCS_1999)) {
            return big5HKSCS
        }
        if let big5 = String(data: data, encoding: cfEncoding(.big5)) {
            return big5
        }
        if let eucJP = String(data: data, encoding: .japaneseEUC) {
            return eucJP
        }

        if let windowsVietnamese = String(data: data, encoding: cfEncoding(.windowsVietnamese)) {
            return windowsVietnamese
        }
        if let viscii = String(data: data, encoding: cfEncoding(.VISCII)) {
            return viscii
        }

        if let isoLatin1 = String(data: data, encoding: .isoLatin1) {
            return isoLatin1
        }
        if let cp1250 = String(data: data, encoding: .windowsCP1250) {
            return cp1250
        }
        if let cp1251 = String(data: data, encoding: .windowsCP1251) {
            return cp1251
        }
        if let cp1252 = String(data: data, encoding: .windowsCP1252) {
            return cp1252
        }
        if let cp1253 = String(data: data, encoding: .windowsCP1253) {
            return cp1253
        }
        if let cp1254 = String(data: data, encoding: .windowsCP1254) {
            return cp1254
        }
        if let asciiStr = String(data: data, encoding: .ascii) {
            return asciiStr
        }

        return ""
    }

    private static func cfEncoding(_ cf: CFStringEncodings) -> String.Encoding {
        let rawValue = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue))
        return String.Encoding(rawValue: rawValue)
    }

    private static func stripBOM(_ text: String?) -> String? {
        guard var text else { return nil }
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return text
    }
}