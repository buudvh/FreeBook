import Foundation

/// Giải nén EPUB (thực chất là ZIP) và định vị file OPF bên trong.
///
/// **Không** `import ZIPFoundation` ở đây: `BackupZipArchive` là file duy nhất trong repo được phép
/// gọi thư viện đó (chữ ký `Archive.init` đổi giữa 0.9.18 và 0.9.19, `Package.resolved` không commit).
enum EpubArchiveReader {
    /// Cây file đã giải nén. Caller **phải** tự xoá `rootDirectory` khi xong (xem `EpubBookParser`).
    struct Package {
        let rootDirectory: URL
        let opfURL: URL

        var opfDirectory: URL { opfURL.deletingLastPathComponent() }

        /// Giải một `href` tương đối thành URL thật trên đĩa. `base` mặc định là thư mục chứa OPF;
        /// href trong NCX/nav phải giải theo thư mục của chính file mục lục đó.
        /// Trả `nil` nếu file không tồn tại **hoặc** đường dẫn thoát ra ngoài `rootDirectory`
        /// (chặn zip-slip kiểu `../../`), cùng tinh thần `validatePathSafety` của các owner khác.
        func resolve(href: String, base: URL? = nil) -> URL? {
            let cleaned = href
                .components(separatedBy: "#").first?
                .removingPercentEncoding ?? href
            guard !cleaned.isEmpty else { return nil }

            let candidate = (base ?? opfDirectory).appendingPathComponent(cleaned).standardizedFileURL
            let root = rootDirectory.standardizedFileURL
            guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
                AppLogger.shared.log("⚠️ [EpubImport] Bỏ qua href thoát khỏi archive: \(href)")
                return nil
            }
            guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
            return candidate
        }
    }

    static func read(fileUrl: URL) throws -> Package {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-epub", isDirectory: true)

        do {
            try BackupZipArchive.extract(archive: fileUrl, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw BookImportService.ImportError.malformed("không giải nén được EPUB (\(error.localizedDescription))")
        }

        guard let opfURL = locateOpf(in: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw BookImportService.ImportError.malformed("không tìm thấy file OPF trong EPUB")
        }
        return Package(rootDirectory: destination, opfURL: opfURL)
    }

    // MARK: - Định vị OPF

    private static func locateOpf(in root: URL) -> URL? {
        if let fromContainer = opfPathFromContainer(root: root) {
            let candidate = root.appendingPathComponent(fromContainer).standardizedFileURL
            if candidate.path.hasPrefix(root.standardizedFileURL.path),
               FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return firstOpf(in: root)
    }

    /// `META-INF/container.xml` → `<rootfile full-path="…">`. File này rất nhỏ và cố định nên đọc
    /// bằng regex, khỏi dựng thêm một delegate `XMLParser`.
    private static func opfPathFromContainer(root: URL) -> String? {
        let containerURL = root.appendingPathComponent("META-INF/container.xml")
        guard let data = try? Data(contentsOf: containerURL),
              let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let regex = try? NSRegularExpression(
                  pattern: "full-path\\s*=\\s*[\"']([^\"']+)[\"']",
                  options: [.caseInsensitive]
              )
        else { return nil }

        let ns = xml as NSString
        guard let match = regex.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1)).removingPercentEncoding
    }

    private static func firstOpf(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "opf" {
                return url
            }
        }
        return nil
    }
}
