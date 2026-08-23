import Foundation
import UniformTypeIdentifiers

/// Các định dạng file sách mà app nhập được từ máy.
///
/// Nhận diện ưu tiên theo đuôi file (người dùng chọn từ app Files nên đuôi đáng tin), chỉ khi
/// đuôi lạ mới soi magic bytes — tránh nhận nhầm một file `.txt` mở đầu bằng `<html>`.
enum BookImportFormat: String, Sendable, CaseIterable {
    case txt
    case html
    case epub
    case mobi

    var displayName: String {
        switch self {
        case .txt: return "TXT"
        case .html: return "HTML"
        case .epub: return "EPUB"
        case .mobi: return "MOBI/AZW3"
        }
    }

    /// Các loại file cho `DocumentPicker` của Kệ sách. `mobi`/`azw3`/`azw` không phải UTI hệ thống nên
    /// dựng bằng `UTType(filenameExtension:conformingTo:)` — trả về dynamic UTI, picker vẫn lọc đúng
    /// theo đuôi file. **Không** dùng `UTType(exportedAs:)` vì app không khai type đó trong `Info.plist`.
    static var pickerContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .html, .epub]
        for ext in ["mobi", "azw3", "azw"] {
            if let type = UTType(filenameExtension: ext, conformingTo: .data) {
                types.append(type)
            }
        }
        return types
    }

    /// Nhận diện format của file đã copy vào thư mục tạm.
    static func detect(fileName: String, data: Data) -> BookImportFormat {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "epub":
            return .epub
        case "html", "htm", "xhtml":
            return .html
        case "mobi", "azw3", "azw", "prc":
            return .mobi
        case "txt":
            return .txt
        default:
            return detectByMagic(data)
        }
    }

    private static func detectByMagic(_ data: Data) -> BookImportFormat {
        let base = data.startIndex

        // ZIP ⇒ coi là EPUB (định dạng ZIP duy nhất đường nhập này nhận)
        if data.count >= 4,
           data[base] == 0x50, data[base + 1] == 0x4B,
           data[base + 2] == 0x03, data[base + 3] == 0x04 {
            return .epub
        }

        // PalmDB: type + creator nằm ở byte 60...67
        if data.count >= 68 {
            let signature = String(decoding: data[(base + 60)..<(base + 68)], as: UTF8.self)
            if signature == "BOOKMOBI" || signature == "TEXtREAd" {
                return .mobi
            }
        }

        // HTML: soi 1 KB đầu
        let headLength = min(1024, data.count)
        let head = String(decoding: data[base..<(base + headLength)], as: UTF8.self).lowercased()
        if head.contains("<html") || head.contains("<!doctype html") || head.contains("<?xml") {
            return .html
        }

        return .txt
    }
}
