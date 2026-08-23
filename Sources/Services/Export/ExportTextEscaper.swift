import Foundation

/// Escape text chương trước khi nhúng vào XML/XHTML/HTML của bản xuất.
///
/// Ngoài 5 thực thể bắt buộc, hàm còn **bỏ ký tự điều khiển** (ngoại trừ tab/CR/LF): nội dung chương lấy
/// từ web đôi khi lẫn `\u{0}`–`\u{8}` hoặc `\u{B}`, và một ký tự như vậy làm EPUB/FB2 sai chuẩn XML
/// (máy đọc từ chối mở cả file), trong khi bản xuất TXT thì không quan tâm.
///
/// Dấu nháy đơn dùng `&#39;` chứ không phải `&apos;` để cùng một hàm dùng được cho cả XML (EPUB/FB2) và
/// HTML của MOBI — `&apos;` không phải thực thể của HTML4.
enum ExportTextEscaper {
    static func xml(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count + text.count / 8)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default:
                if isAllowedInXml(scalar) {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    private static func isAllowedInXml(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D:
            return true
        case 0x00...0x1F, 0x7F...0x9F:
            return false
        default:
            return true
        }
    }
}
