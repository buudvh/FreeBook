import Foundation

/// Cửa ghi **duy nhất** cho gói tiện ích JS (`ExtensionPackageBundle`, file `extensions/js/<packageId>.json`) — đọc
/// thì qua `ExtensionPackageReader`.
///
/// - **Gom** (`makeBundle`): `plugin.json` (nguyên văn), mọi file `*.js` (giữ đường dẫn tương đối) và `icon.png`
///   (base64) của một thư mục đã giải nén / giải mã. File khác bị bỏ: JS chỉ đọc file qua `load()`, mà `load()` chỉ
///   chạy file JS. Bytes đổi sang chữ bằng `TextEncodingDecoder.decode` (cùng hàm `JSExecutor.decodeData`: bảng mã
///   khác UTF-8, BOM). Giải mã không ra chữ ⇒ **ném**, không gom thiếu — thư mục cũ bị xoá sau khi chuyển, gom hỏng
///   là mất tiện ích.
/// - **Ghi tuần tự**: mọi lần ghi (cài, cài nháp, trình sửa script, sửa metadata, khôi phục backup) chạy trên
///   **một** hàng đợi `queue` ⇒ hai lần sửa cùng gói không đè mất nhau (mỗi lần sửa là ghi lại cả file). Ghi nguyên tử
///   (`.atomic`: file tạm cùng thư mục rồi thay), ghi đè được. `makeBundle` không đụng hàng đợi nên gọi được từ
///   migrator / backup mà không lồng `queue.sync`.
/// - Gói dạng **thư mục** (nháp debug, bản ghi chuyển lỗi) vẫn sửa được: ghi thẳng file trong thư mục. Nguồn Legado
///   không sửa qua đây (`LegadoSourceStore`).
enum ExtensionPackageWriter {
    enum WriteError: LocalizedError {
        case missingManifest
        case undecodableText(String)
        case unsafePackageId(String)
        case notEditable
        case invalidBundle
        case io(String)

        var errorDescription: String? {
            switch self {
            case .missingManifest: return "Không tìm thấy tệp plugin.json của tiện ích"
            case .undecodableText(let path): return "Không đọc được \(path) thành chữ"
            case .unsafePackageId(let id): return "packageId không dùng được làm tên file: \(id)"
            case .notEditable: return "Gói này không sửa được tại chỗ"
            case .invalidBundle: return "Tệp gói tiện ích hỏng"
            case .io(let message): return message
            }
        }
    }

    /// Hàng đợi tuần tự cho mọi lần ghi gói JS. **Không** gọi hàm công khai của type này từ bên trong hàng đợi.
    static let queue = DispatchQueue(label: "TangCongCac.ExtensionPackageWriter", qos: .userInitiated)

    // MARK: - Gom

    /// Gói từ một thư mục có `plugin.json`. Không đụng hàng đợi, không ghi gì.
    static func makeBundle(fromDirectory directory: URL) throws -> ExtensionPackageBundle {
        let path = directory.path
        guard ExtensionPackageReader.layout(localPath: path) == .directory,
              ExtensionPackageReader.isPresent(localPath: path) else { throw WriteError.missingManifest }
        var files: [String: String] = [:]
        for relative in ExtensionPackageReader.listFiles(localPath: path) {
            guard let data = ExtensionPackageReader.fileData(relativePath: relative, localPath: path) else {
                throw WriteError.io("Không đọc được \(relative)")
            }
            files[relative] = try text(from: data, relativePath: relative)
        }
        guard files[ExtensionPackageBundle.manifestPath] != nil else { throw WriteError.missingManifest }
        let icon = ExtensionPackageReader.iconData(localPath: path)?.base64EncodedString()
        return ExtensionPackageBundle(files: files, icon: icon)
    }

    /// Bytes → chữ như `JSExecutor.decodeData`. File rỗng ⇒ `""`; có bytes mà không bảng mã nào giải được ⇒ ném.
    static func text(from data: Data, relativePath: String) throws -> String {
        guard !data.isEmpty else { return "" }
        let text = TextEncodingDecoder.decode(data)
        guard !text.isEmpty else { throw WriteError.undecodableText(relativePath) }
        return text
    }

    // MARK: - Ghi (tuần tự)

    /// Gom `directory` rồi ghi `extensions/js/<packageId>.json` (ghi đè bản cũ). Trả URL file đã ghi.
    @discardableResult
    static func install(directory: URL, packageId: String) throws -> URL {
        guard let target = ExtensionFolderLocator.jsPackageURL(packageId: packageId) else {
            throw WriteError.unsafePackageId(packageId)
        }
        let bundle = try makeBundle(fromDirectory: directory)
        try queue.sync { try performWrite(bundle, to: target) }
        return target
    }

    /// Ghi một gói đã dựng sẵn vào `target` (ghi đè).
    static func write(_ bundle: ExtensionPackageBundle, to target: URL) throws {
        try queue.sync { try performWrite(bundle, to: target) }
    }

    /// Ghi bytes nguyên văn của một file gói (bản sao lưu / backup) vào `target` sau khi kiểm bytes đó là gói hợp lệ.
    static func writePackageData(_ data: Data, to target: URL) throws {
        guard (try? ExtensionPackageBundle.decode(from: data)) != nil else { throw WriteError.invalidBundle }
        try queue.sync { try performWrite(data: data, to: target) }
    }

    /// Ghi đè **một** file trong gói ở `localPath` (trình sửa script).
    static func writeFile(relativePath: String, text: String, localPath: String) throws {
        try modifyFile(relativePath: relativePath, localPath: localPath) { _ in text }
    }

    /// Đọc – sửa – ghi **một** file trong gói, cả ba bước trong hàng đợi. `transform` nhận bytes hiện tại (`nil` khi
    /// file chưa có), trả chữ mới hoặc `nil` = không đổi (không ghi). Trả `true` khi đã ghi.
    @discardableResult
    static func modifyFile(
        relativePath: String,
        localPath: String,
        _ transform: (Data?) throws -> String?
    ) throws -> Bool {
        guard let relative = ExtensionPackageReader.normalizedRelativePath(relativePath),
              ExtensionPackageReader.isPackagedFile(relative) else { throw WriteError.notEditable }
        return try queue.sync {
            let url = URL(fileURLWithPath: localPath)
            switch ExtensionPackageReader.layout(localPath: localPath) {
            case .directory:
                let fileURL = url.appendingPathComponent(relative)
                guard let newText = try transform(try? Data(contentsOf: fileURL)) else { return false }
                try performWrite(data: Data(newText.utf8), to: fileURL)
                return true
            case .jsBundle:
                guard let data = try? Data(contentsOf: url),
                      var bundle = try? ExtensionPackageBundle.decode(from: data) else { throw WriteError.invalidBundle }
                guard let newText = try transform(bundle.files[relative].map { Data($0.utf8) }) else { return false }
                bundle.files[relative] = newText
                try performWrite(bundle, to: url)
                return true
            case .legadoSource, nil:
                throw WriteError.notEditable
            }
        }
    }

    // MARK: - Riêng (chỉ trên hàng đợi)

    private static func performWrite(_ bundle: ExtensionPackageBundle, to target: URL) throws {
        let data: Data
        do {
            data = try bundle.encodedData()
        } catch {
            throw WriteError.io("Không mã hoá được gói: \(error.localizedDescription)")
        }
        try performWrite(data: data, to: target)
    }

    private static func performWrite(data: Data, to target: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: target, options: [.atomic])
        } catch {
            AppLogger.shared.log("❌ 🧩 [ExtPackage] Không ghi được \(target.lastPathComponent): \(error.localizedDescription)")
            throw WriteError.io(error.localizedDescription)
        }
        ExtensionPackageBundleCache.shared.remove(path: target.standardizedFileURL.path)
    }
}
