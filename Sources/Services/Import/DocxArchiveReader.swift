import Foundation

/// Giải nén DOCX (OOXML là ZIP) và đọc **đúng hai entry cần dùng** vào RAM: `word/document.xml`
/// (thân tài liệu) và `docProps/core.xml` (tên sách / tác giả).
///
/// Thư mục tạm bị xoá ngay trong `defer` nên caller không phải quản lý vòng đời file nào — khác
/// `EpubArchiveReader` (EPUB phải giữ cây file để giải `href` giữa các XHTML và lấy ảnh bìa).
///
/// Hai tên entry đều là **hằng số** của chuẩn OOXML, không có phần nào do file quyết định, nên không
/// có đường ghép đường dẫn từ dữ liệu không tin cậy ở đây.
///
/// **Không** `import ZIPFoundation`: `BackupZipArchive` là file duy nhất trong repo được phép gọi
/// thư viện đó.
enum DocxArchiveReader {
    struct Package: Sendable {
        let documentXml: Data
        /// `nil` khi file không có phần metadata (hợp lệ — tên sách sẽ lấy từ tên file).
        let coreXml: Data?
    }

    static func read(fileUrl: URL) throws -> Package {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-docx", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        do {
            try BackupZipArchive.extract(archive: fileUrl, to: destination)
        } catch {
            throw BookImportService.ImportError.malformed(
                "không giải nén được DOCX (\(error.localizedDescription))"
            )
        }

        guard let documentXml = BackupZipArchive.readStaged(
            entryName: "word/document.xml",
            in: destination
        ) else {
            // `.doc` cũ (OLE2) và DOCX có DRM đều rơi vào đây.
            throw BookImportService.ImportError.malformed(
                "không thấy word/document.xml — file không phải DOCX chuẩn (định dạng .doc cũ chưa hỗ trợ)"
            )
        }

        return Package(
            documentXml: documentXml,
            coreXml: BackupZipArchive.readStaged(entryName: "docProps/core.xml", in: destination)
        )
    }
}
