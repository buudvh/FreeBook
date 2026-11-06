import Foundation

/// Bộ đọc **duy nhất** cho nội dung một gói tiện ích theo `localPath` (= `Extension.localPath`): `plugin.json`, script JS,
/// icon. Nơi khác không tự ghép `plugin.json` / `src/` / `icon.png` vào `localPath`.
///
/// Ba dạng gói, phân biệt theo đường dẫn:
/// - **thư mục** (bố cục cũ, và thư mục nháp của debug server): `plugin.json` + script ở gốc hoặc `src/` + `icon.png` ở gốc;
/// - **file `.json` nằm trong thư mục `legado/`**: nguyên văn `source.json` của một nguồn Legado. Manifest dựng trong RAM
///   (`LegadoSourceManifest` — không có `version` / `nsfw`), không có script hay icon;
/// - **file `.json` khác**: gói tiện ích JS (`ExtensionPackageBundle`).
///
/// Thuần, an toàn đa luồng, gọi được từ thread bất kỳ. Gói JS đã parse được nhớ trong RAM (`ExtensionPackageBundleCache`),
/// khoá theo (đường dẫn, mtime, cỡ): mỗi lần đọc tốn một `stat()`; `stat()` lỗi ⇒ coi như **không có gói**, không bao giờ
/// trả bản đã nhớ. Nguồn Legado không nhớ. Không log (Models không phụ thuộc Services): lỗi trả `nil`, caller tự báo.
public enum ExtensionPackageReader {
    public enum Layout: Sendable, Equatable {
        case directory
        case jsBundle
        case legadoSource
    }

    /// Một script tìm thấy trong gói.
    public struct Script: Sendable {
        /// Đường dẫn tương đối trong gói (`search.js`, `src/search.js`), đã bỏ `./` và `//` khi chuẩn hoá được.
        public let relativePath: String
        public let data: Data

        /// Tên file (`search.js`, kể cả khi nằm trong `src/`) — cho log, như `lastPathComponent` trước đây.
        public var fileName: String {
            (relativePath as NSString).lastPathComponent
        }

        /// Chữ UTF-8 **chặt**, cùng cách đọc `String(contentsOf:encoding: .utf8)` trước đây: bytes không hợp lệ ⇒ ném.
        /// (`load()` của thư viện thì đi `JSExecutor.decodeData`, khoan dung bảng mã.)
        public func text() throws -> String {
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return text
        }
    }

    /// Mốc kiểm hạn cho cache của caller — so bằng `==`.
    public struct Stamp: Hashable, Sendable {
        let parts: [Double]
    }

    public static let manifestFileName = ExtensionPackageBundle.manifestPath
    public static let iconFileName = ExtensionPackageBundle.iconPath
    /// Thư mục cha của file nguồn Legado (`extensions/legado/<packageId>.json`).
    public static let legadoFolderName = "legado"
    /// Tên file nguồn trong thư mục Legado cũ; với dạng một file thì chính là file gói (`fileData(relativePath:)`).
    public static let legadoSourceFileName = "source.json"
    /// Thư mục dự phòng của script, sau gốc gói.
    public static let scriptFolderName = "src"
    private static let packageFileExtension = "json"

    // MARK: - Nhận dạng

    /// Dạng gói của `localPath`; `nil` khi đường dẫn rỗng, không tồn tại, hoặc là file không phải `.json`.
    public static func layout(localPath: String) -> Layout? {
        locate(localPath)?.layout
    }

    /// Gói có trên máy: thư mục có `plugin.json`, hoặc file gói tồn tại.
    public static func isPresent(localPath: String) -> Bool {
        guard let location = locate(localPath) else { return false }
        switch location.layout {
        case .directory: return isRegularFile(location.url.appendingPathComponent(manifestFileName))
        case .jsBundle, .legadoSource: return true
        }
    }

    /// Tên ngắn của gói cho log, lỗi, khoá cache: tên thư mục, hoặc tên file bỏ đuôi `.json` (= `packageId` ở bố cục một
    /// file). Không chạm đĩa; thư mục cho cùng kết quả như `lastPathComponent` trước đây.
    public static func packageName(localPath: String) -> String {
        let path = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard (name as NSString).pathExtension.lowercased() == packageFileExtension else { return name }
        return (name as NSString).deletingPathExtension
    }

    // MARK: - Manifest

    /// Bytes `plugin.json`: nguyên văn với thư mục / gói JS, dựng trong RAM với nguồn Legado. `nil` khi không có.
    public static func manifestData(localPath: String) -> Data? {
        locate(localPath).flatMap(manifestData(at:))
    }

    /// `plugin.json` dạng object; `nil` khi không có, hỏng, hoặc không phải object.
    public static func manifest(localPath: String) -> [String: Any]? {
        guard let location = locate(localPath) else { return nil }
        if location.layout == .legadoSource {
            return legadoSource(at: location.url)
                .flatMap(LegadoSourceManifest.metadata(source:))
                .map { metadata -> [String: Any] in ["metadata": metadata] }
        }
        guard let data = manifestData(at: location) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// `metadata` của `plugin.json`, thiếu thì dùng gốc file — giống luồng cài.
    public static func metadata(localPath: String) -> [String: Any]? {
        guard let json = manifest(localPath: localPath) else { return nil }
        return json["metadata"] as? [String: Any] ?? json
    }

    // MARK: - Script

    /// Script theo tên ở **gốc gói rồi `src/`** — đúng hợp đồng `load()` và mục `script` của `plugin.json`. `nil` khi không
    /// có hoặc không đọc được. Thư mục: ghép tên nguyên văn như trước, file có ở gốc thì không dò tiếp `src/`. Gói JS: tên
    /// được chuẩn hoá (`normalizedRelativePath`), vượt ra ngoài gói ⇒ `nil`.
    public static func script(named name: String, localPath: String) -> Script? {
        guard !name.isEmpty, let location = locate(localPath) else { return nil }
        switch location.layout {
        case .directory:
            for candidate in [name, scriptFolderName + "/" + name] {
                let url = location.url.appendingPathComponent(candidate)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                guard let data = try? Data(contentsOf: url) else { return nil }
                return Script(relativePath: normalizedRelativePath(candidate) ?? candidate, data: data)
            }
            return nil
        case .jsBundle:
            guard let relative = normalizedRelativePath(name), let bundle = bundle(at: location) else { return nil }
            for candidate in [relative, scriptFolderName + "/" + relative] {
                if let text = bundle.files[candidate] { return Script(relativePath: candidate, data: Data(text.utf8)) }
            }
            return nil
        case .legadoSource:
            return nil
        }
    }

    public static func scriptData(named name: String, localPath: String) -> Data? {
        script(named: name, localPath: localPath)?.data
    }

    /// Tên file mà mục `script` của `plugin.json` khai cho `key` (`search`, `tts`…), nguyên văn. `nil` khi không khai hoặc
    /// giá trị không phải chuỗi (map có thể lẫn giá trị lạ — không ép `[String: String]`).
    public static func scriptFileName(forKey key: String, localPath: String) -> String? {
        (manifest(localPath: localPath)?["script"] as? [String: Any])?[key] as? String
    }

    // MARK: - File & icon

    /// File theo đường dẫn tương đối **chính xác** (không dò `src/`). `icon.png` đọc được ở mọi dạng có icon; nguồn Legado
    /// có `plugin.json` (dựng trong RAM) và `source.json` (nguyên văn). Vượt ra ngoài gói ⇒ `nil`.
    public static func fileData(relativePath: String, localPath: String) -> Data? {
        guard let relative = normalizedRelativePath(relativePath), let location = locate(localPath) else { return nil }
        switch location.layout {
        case .directory:
            return readFile(location.url.appendingPathComponent(relative))
        case .jsBundle:
            guard let bundle = bundle(at: location) else { return nil }
            if relative == iconFileName { return bundle.iconData }
            return bundle.files[relative].map { Data($0.utf8) }
        case .legadoSource:
            switch relative {
            case manifestFileName: return manifestData(at: location)
            case legadoSourceFileName: return readFile(location.url)
            default: return nil
            }
        }
    }

    public static func iconData(localPath: String) -> Data? {
        fileData(relativePath: iconFileName, localPath: localPath)
    }

    /// Đường dẫn tương đối của `plugin.json` (khi có, chỉ ở gốc) và mọi file `.js`, đã sắp xếp — cho trình sửa script và bộ
    /// quét. Đúng tập file mà gói JS mang. Nguồn Legado chỉ có `plugin.json` (dựng trong RAM, không sửa được).
    public static func listFiles(localPath: String) -> [String] {
        guard let location = locate(localPath) else { return [] }
        switch location.layout {
        case .directory: return listDirectory(location.url)
        case .jsBundle: return bundle(at: location).map { $0.files.keys.filter(isPackagedFile).sorted() } ?? []
        case .legadoSource: return [manifestFileName]
        }
    }

    /// File thuộc gói JS: `plugin.json` ở gốc hoặc file `.js` bất kỳ (giữ đường dẫn tương đối).
    public static func isPackagedFile(_ relativePath: String) -> Bool {
        relativePath == manifestFileName || (relativePath as NSString).pathExtension.lowercased() == "js"
    }

    // MARK: - Mốc kiểm hạn

    /// Mốc kiểm hạn cho cache của caller:
    /// - file gói (JS, Legado): (mtime, cỡ) của chính file — mọi phần của gói nằm trong đó, `relativePaths` bỏ qua;
    /// - thư mục: mtime của từng file trong `relativePaths`; file thiếu ⇒ 0 (như mốc cũ của các cache).
    /// `nil` khi không có gói (đường dẫn không tồn tại / `stat` lỗi) ⇒ caller không được dùng bản đã nhớ.
    public static func modificationStamp(
        localPath: String,
        relativePaths: [String] = [ExtensionPackageReader.manifestFileName]
    ) -> Stamp? {
        guard let location = locate(localPath) else { return nil }
        switch location.layout {
        case .jsBundle, .legadoSource:
            return Stamp(parts: [location.modifiedAt, Double(location.size)])
        case .directory:
            return Stamp(parts: relativePaths.map { modifiedAt(location.url.appendingPathComponent($0).path) ?? 0 })
        }
    }

    // MARK: - Đường dẫn

    /// `./a//b.js` → `a/b.js`; `x/../y.js` → `y.js`; rỗng hoặc `..` vượt ra ngoài gốc ⇒ `nil`.
    public static func normalizedRelativePath(_ path: String) -> String? {
        var parts: [Substring] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default:
                parts.append(component)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    // MARK: - Riêng

    private struct Location {
        let url: URL
        let layout: Layout
        /// Chỉ có nghĩa với file gói (thư mục ⇒ 0).
        let modifiedAt: Double
        let size: Int64
    }

    /// Một lần `stat` (theo symlink ở thành phần cuối): dạng gói + (mtime, cỡ) của file gói. `nil` khi đường dẫn rỗng, không
    /// tồn tại, hoặc là file không phải `.json`. File `.json` mất ⇒ bỏ luôn bản đã nhớ của nó.
    private static func locate(_ localPath: String) -> Location? {
        let path = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let isPackageFile = url.pathExtension.lowercased() == packageFileExtension
        var info = try? FileManager.default.attributesOfItem(atPath: url.path)
        if info?[.type] as? FileAttributeType == .typeSymbolicLink {
            info = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)
        }
        guard let attributes = info else {
            if isPackageFile { ExtensionPackageBundleCache.shared.remove(path: url.standardizedFileURL.path) }
            return nil
        }
        if attributes[.type] as? FileAttributeType == .typeDirectory {
            return Location(url: url, layout: .directory, modifiedAt: 0, size: 0)
        }
        guard isPackageFile,
              let modified = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.int64Value else { return nil }
        let isLegado = url.deletingLastPathComponent().lastPathComponent == legadoFolderName
        return Location(
            url: url,
            layout: isLegado ? .legadoSource : .jsBundle,
            modifiedAt: modified.timeIntervalSince1970,
            size: size
        )
    }

    private static func manifestData(at location: Location) -> Data? {
        switch location.layout {
        case .directory: return readFile(location.url.appendingPathComponent(manifestFileName))
        case .jsBundle: return bundle(at: location)?.manifestText.map { Data($0.utf8) }
        case .legadoSource: return legadoSource(at: location.url).flatMap(LegadoSourceManifest.manifestData(source:))
        }
    }

    private static func bundle(at location: Location) -> ExtensionPackageBundle? {
        ExtensionPackageBundleCache.shared.bundle(at: location.url, modifiedAt: location.modifiedAt, size: location.size)
    }

    /// Nguồn Legado parse từ file mỗi lần gọi (không nhớ — hàng nghìn nguồn).
    private static func legadoSource(at url: URL) -> LegadoBookSource? {
        guard let data = readFile(url) else { return nil }
        return try? LegadoBookSource(data: data)
    }

    private static func readFile(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private static func modifiedAt(_ path: String) -> Double? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970
    }

    /// Duyệt cả cây thư mục, bỏ mục ẩn (và nhánh bên dưới thư mục ẩn).
    private static func listDirectory(_ root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var result: [String] = []
        while let relative = enumerator.nextObject() as? String {
            let isDirectory = enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            if relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            guard !isDirectory, isPackagedFile(relative) else { continue }
            result.append(relative)
        }
        return result.sorted()
    }
}
