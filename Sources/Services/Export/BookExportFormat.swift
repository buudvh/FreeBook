import Foundation

/// Định dạng file mà một tác vụ **xuất truyện** tạo ra.
///
/// Format là thuộc tính của *tác vụ*, nên nó được lưu bền qua `TaskType.rawValue` trong
/// `DownloadTaskModel.taskTypeRaw` (một cột `String` đã có) — không cần thêm field mới vào schema
/// SwiftData. Nhờ vậy tác vụ xuất vẫn biết mình phải render định dạng nào sau khi app khởi động lại
/// và người dùng bấm "Tải lại tác vụ".
///
/// Truyện chữ: TXT, EPUB 3, FB2, MOBI (`ExportRendererFactory`). Truyện tranh: CBZ và PDF, chỉ từ chương đã tải ảnh
/// offline (`DownloadManager+ComicExport`). Video không xuất. Picker định dạng lọc theo loại qua `formats(for:)`.
public enum BookExportFormat: String, CaseIterable, Sendable {
    case txt
    case epub3
    case fb2
    case mobi
    case cbz
    case pdf

    /// Các định dạng hợp với loại nội dung của sách (video: rỗng).
    public static func formats(for kind: ExtensionContentKind) -> [BookExportFormat] {
        switch kind {
        case .comic: return [.cbz, .pdf]
        case .video: return []
        case .text, .unsupported: return [.txt, .epub3, .fb2, .mobi]
        }
    }

    /// Định dạng ảnh của truyện tranh — không đi qua `ExportRendererFactory`.
    public var isComicFormat: Bool {
        self == .cbz || self == .pdf
    }

    /// Tên hiện trên UI (picker định dạng ở sheet tuỳ chọn).
    public var displayName: String {
        switch self {
        case .txt: return "TXT"
        case .epub3: return "EPUB 3"
        case .fb2: return "FB2"
        case .mobi: return "MOBI"
        case .cbz: return "CBZ"
        case .pdf: return "PDF"
        }
    }

    /// Đuôi file của artifact.
    public var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .epub3: return "epub"
        case .fb2: return "fb2"
        case .mobi: return "mobi"
        case .cbz: return "cbz"
        case .pdf: return "pdf"
        }
    }

    /// Loại tác vụ tương ứng — đây là giá trị được ghi vào CSDL.
    public var taskType: TaskType {
        switch self {
        case .txt: return .exportTxt
        case .epub3: return .exportEpub
        case .fb2: return .exportFb2
        case .mobi: return .exportMobi
        case .cbz: return .exportCbz
        case .pdf: return .exportPdf
        }
    }

    /// Format có nhúng được ảnh bìa hay không (TXT thì không).
    public var supportsCover: Bool {
        switch self {
        case .txt, .cbz, .pdf: return false
        case .epub3, .fb2, .mobi: return true
        }
    }

    /// Format có mục lục điều hướng được hay không.
    public var supportsNavigation: Bool {
        switch self {
        case .txt, .cbz, .pdf: return false
        case .epub3, .fb2, .mobi: return true
        }
    }

    /// Mô tả ngắn hiện ở phần chú thích của sheet tuỳ chọn.
    public var summary: String {
        switch self {
        case .txt: return "Văn bản thuần UTF-8, mở được ở mọi nơi."
        case .epub3: return "Chuẩn EPUB 3: metadata, mục lục điều hướng, bìa, mỗi chương một XHTML."
        case .fb2: return "FictionBook 2: một file XML, có metadata, mục lục và bìa nhúng."
        case .mobi: return "MOBI cho Kindle: không nén, có mục lục và bìa nhúng."
        case .cbz: return "CBZ: ảnh gốc gói trong ZIP, mỗi chương một thư mục — mở được ở các app đọc truyện tranh."
        case .pdf: return "PDF: mỗi ảnh một trang, theo thứ tự chương."
        }
    }
}
