import Foundation
import UniformTypeIdentifiers

/// Phân loại các file người dùng chọn ở Kệ sách **theo đuôi**, trước khi `BookImportService` chạm tới file.
///
/// Luật (người dùng chốt):
/// - Một file `.cbz`/`.zip` = **cả bộ** truyện tranh (`LocalComicImporter`). Riêng `.zip` mà mở đầu là EPUB
///   (`mimetype` = `application/epub+zip`) vẫn đi luồng chữ như trước.
/// - Video `.mp4`/`.mov`/`.m4v`: một hay nhiều file đều gộp thành **một** phim (`LocalVideoImporter`).
/// - Chọn nhiều file chỉ hợp lệ khi **tất cả** là video; lẫn loại ⇒ từ chối, không nhập gì.
/// - Còn lại (một file) ⇒ luồng chữ cũ (`importLocalBook`). Không nhận CBR/RAR/7z.
enum LocalMediaImportRoute {
    case text(URL)
    case comic(URL)
    case video([URL])
    case rejected(String)

    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let comicExtensions: Set<String> = ["cbz", "zip"]

    /// Loại file cho `DocumentPicker` của Kệ sách: định dạng chữ cũ + CBZ/ZIP + ba loại video.
    static var pickerContentTypes: [UTType] {
        var types = BookImportFormat.pickerContentTypes
        types.append(.zip)
        types.append(.mpeg4Movie)
        types.append(.quickTimeMovie)
        for ext in ["cbz", "m4v"] {
            if let type = UTType(filenameExtension: ext, conformingTo: .data) {
                types.append(type)
            }
        }
        return types
    }

    /// `nil` khi không có file nào.
    static func route(for urls: [URL]) -> LocalMediaImportRoute? {
        guard let first = urls.first else { return nil }
        let extensions = urls.map { $0.pathExtension.lowercased() }
        if extensions.allSatisfy({ videoExtensions.contains($0) }) {
            return .video(urls)
        }
        guard urls.count == 1 else {
            return .rejected("Chỉ chọn nhiều file khi tất cả đều là video (MP4/MOV/M4V) — chưa nhập file nào.")
        }
        guard comicExtensions.contains(extensions[0]) else { return .text(first) }
        if extensions[0] == "zip", looksLikeEpub(first) {
            return .text(first)
        }
        return .comic(first)
    }

    /// So tên kiểu Finder: "Tập 2" đứng trước "Tập 10".
    static func naturalLess(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    /// Bản chép tạm của bộ chọn file (`asCopy: true`) thuộc về app — bỏ đi khi không nhập.
    static func discardPickedCopies(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// EPUB đặt entry `mimetype` (không nén) đầu tiên ⇒ chuỗi `epub+zip` nằm trong vài chục byte đầu
    /// (cùng cách dò của `BookImportFormat.detectZipFamily`). Chỉ đọc 512 byte.
    private static func looksLikeEpub(_ url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 512)) ?? Data()
        return head.range(of: Data("epub+zip".utf8)) != nil
    }
}
