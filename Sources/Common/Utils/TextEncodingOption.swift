import Foundation

/// Bảng mã giải mã có thể chọn thủ công cho file TXT.
/// `allCases` giữ đúng thứ tự ưu tiên của quá trình auto-detect: UTF-8/BOM trước,
/// kế tiếp là các mã đa byte (CJK) vì chúng fail khi gặp chuỗi byte không hợp lệ,
/// cuối cùng là mã đơn byte (thường không bao giờ fail) để tránh nuốt nhầm file
/// tiếng Trung thành Latin-1/CP125x.
enum TextEncodingOption: String, CaseIterable, Identifiable {
    case utf8
    case utf16LE
    case utf16BE
    case utf32LE
    case utf32
    case utf32BE
    case gb18030
    case gbk
    case big5HKSCS
    case big5
    case eucJP
    case windowsVietnamese
    case viscii
    case isoLatin1
    case windows1250
    case windows1251
    case windows1252
    case windows1253
    case windows1254
    case ascii

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16LE: return "UTF-16 LE"
        case .utf16BE: return "UTF-16 BE"
        case .utf32LE: return "UTF-32 LE"
        case .utf32: return "UTF-32 (BOM)"
        case .utf32BE: return "UTF-32 BE"
        case .gb18030: return "GB18030"
        case .gbk: return "GBK"
        case .big5HKSCS: return "Big5-HKSCS"
        case .big5: return "Big5"
        case .eucJP: return "EUC-JP"
        case .windowsVietnamese: return "Windows Vietnamese (CP1258)"
        case .viscii: return "VISCII (TCVN3)"
        case .isoLatin1: return "ISO-8859-1 (Latin-1)"
        case .windows1250: return "Windows-1250"
        case .windows1251: return "Windows-1251"
        case .windows1252: return "Windows-1252"
        case .windows1253: return "Windows-1253"
        case .windows1254: return "Windows-1254"
        case .ascii: return "ASCII"
        }
    }

    /// Giải mã `Data` bằng đúng bảng mã này. Trả về `nil` nếu không hợp lệ.
    func decode(_ data: Data) -> String? {
        switch self {
        case .utf8:
            return String(data: data, encoding: .utf8)
        case .utf16LE:
            return TextEncodingDecoder.stripBOM(String(data: data, encoding: .utf16LittleEndian))
        case .utf16BE:
            return TextEncodingDecoder.stripBOM(String(data: data, encoding: .utf16BigEndian))
        case .utf32LE:
            return TextEncodingDecoder.stripBOM(String(data: data, encoding: .utf32LittleEndian))
        case .utf32:
            return TextEncodingDecoder.stripBOM(String(data: data, encoding: .utf32))
        case .utf32BE:
            return TextEncodingDecoder.stripBOM(String(data: data, encoding: .utf32BigEndian))
        case .gb18030:
            return String(data: data, encoding: TextEncodingDecoder.cfEncoding(.GB_18030_2000))
        case .gbk:
            return String(data: data, encoding: TextEncodingDecoder.cfEncoding(.GBK_95))
        case .big5HKSCS:
            return String(data: data, encoding: TextEncodingDecoder.cfEncoding(.big5_HKSCS_1999))
        case .big5:
            return String(data: data, encoding: TextEncodingDecoder.cfEncoding(.big5))
        case .eucJP:
            return String(data: data, encoding: .japaneseEUC)
        case .windowsVietnamese:
            return String(data: data, encoding: TextEncodingDecoder.cfEncoding(.windowsVietnamese))
        case .viscii:
            return String(data: data, encoding: TextEncodingDecoder.cfEncoding(.VISCII))
        case .isoLatin1:
            return String(data: data, encoding: .isoLatin1)
        case .windows1250:
            return String(data: data, encoding: .windowsCP1250)
        case .windows1251:
            return String(data: data, encoding: .windowsCP1251)
        case .windows1252:
            return String(data: data, encoding: .windowsCP1252)
        case .windows1253:
            return String(data: data, encoding: .windowsCP1253)
        case .windows1254:
            return String(data: data, encoding: .windowsCP1254)
        case .ascii:
            return String(data: data, encoding: .ascii)
        }
    }
}
