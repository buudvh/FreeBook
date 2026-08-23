import Foundation
import UniformTypeIdentifiers

/// Các định dạng file sách mà app nhập được từ máy.
///
/// Nhận diện ưu tiên theo đuôi file (người dùng chọn từ app Files nên đuôi đáng tin), chỉ khi
/// đuôi lạ mới soi magic bytes — tránh nhận nhầm một file `.txt` mở đầu bằng `<html>`.
///
/// Hai format cùng là ZIP (`epub` và `docx`) nên nhánh magic bytes phải soi thêm *bên trong* archive:
/// EPUB bắt buộc có entry `mimetype` chứa `application/epub+zip` ngay đầu file, DOCX có entry
/// `word/document.xml`.
enum BookImportFormat: String, Sendable, CaseIterable {
    case txt
    case html
    case epub
    case mobi
    case docx
    case fb2

    var displayName: String {
        switch self {
        case .txt: return "TXT"
        case .html: return "HTML"
        case .epub: return "EPUB"
        case .mobi: return "MOBI/AZW3/PRC"
        case .docx: return "DOCX"
        case .fb2: return "FB2"
        }
    }

    /// Các loại file cho `DocumentPicker` của Kệ sách. `mobi`/`azw3`/`azw`/`prc`/`fb2` không phải UTI
    /// hệ thống nên dựng bằng `UTType(filenameExtension:conformingTo:)` — trả về dynamic UTI (hoặc UTI
    /// hệ thống nếu có, như `docx`), picker vẫn lọc đúng theo đuôi file. **Không** dùng
    /// `UTType(exportedAs:)` vì app không khai type đó trong `Info.plist`.
    static var pickerContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .html, .epub]
        for ext in ["mobi", "azw3", "azw", "prc", "docx", "fb2"] {
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
        case "docx":
            return .docx
        case "fb2":
            return .fb2
        case "txt":
            return .txt
        default:
            return detectByMagic(data)
        }
    }

    private static func detectByMagic(_ data: Data) -> BookImportFormat {
        let base = data.startIndex

        // ZIP: EPUB hay DOCX, phân biệt bằng entry bên trong.
        if data.count >= 4,
           data[base] == 0x50, data[base + 1] == 0x4B,
           data[base + 2] == 0x03, data[base + 3] == 0x04 {
            return detectZipFamily(data)
        }

        // PalmDB: type + creator nằm ở byte 60...67
        if data.count >= 68 {
            let signature = String(decoding: data[(base + 60)..<(base + 68)], as: UTF8.self)
            if signature == "BOOKMOBI" || signature == "TEXtREAd" {
                return .mobi
            }
        }

        // FB2 phải xét **trước** HTML: nó là XML nên cũng khớp dấu hiệu `<?xml`.
        let headLength = min(1024, data.count)
        let lowered = String(decoding: data[base..<(base + headLength)], as: UTF8.self).lowercased()
        if lowered.contains("<fictionbook") { return .fb2 }

        if lowered.contains("<html") || lowered.contains("<!doctype html") || lowered.contains("<?xml") {
            return .html
        }

        return .txt
    }

    /// EPUB đặt `mimetype` làm entry đầu tiên **không nén** nên chuỗi `application/epub+zip` nằm ngay
    /// trong vài chục byte đầu; DOCX thì tìm tên entry `word/document.xml` trong local header.
    /// Không giải nén ở bước nhận diện — chỉ dò byte.
    private static func detectZipFamily(_ data: Data) -> BookImportFormat {
        if contains(Data(data.prefix(512)), "epub+zip") { return .epub }
        if contains(data, "word/document.xml") { return .docx }
        return .epub
    }

    private static func contains(_ data: Data, _ needle: String) -> Bool {
        return data.range(of: Data(needle.utf8)) != nil
    }
}
