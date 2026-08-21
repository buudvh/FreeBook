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