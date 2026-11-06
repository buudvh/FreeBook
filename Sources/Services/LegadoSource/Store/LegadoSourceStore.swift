import Foundation

/// Lưu trữ file của nguồn Legado: mỗi nguồn là **một file** `applicationSupport/extensions/legado/<packageId>.json` =
/// object JSON gốc của nguồn (đúng bytes `source.json` cũ, **giữ mọi khoá**, bytes ổn định: khoá sắp xếp).
///
/// - Không còn `plugin.json` sinh tự động (1.3.756): `version` nằm ở bản ghi `installed.json`; `type` và các trường
///   manifest dựng trong RAM (`LegadoSourceManifest`, `ExtensionPackageReader`); cờ 18+ do `makeCommand` tính sẵn
///   (`ExtensionNsfwClassifier.isLegadoNsfw`) — coordinator không đọc manifest của nguồn Legado.
/// - **Vị trí** (`location`) của một nguồn là URL file mới, hoặc thư mục cũ `extensions/<packageId>/` (chứa
///   `source.json`) của bản ghi chưa chuyển (`ExtensionPackageLayoutMigrator`). Đọc / vá / xoá hiểu cả hai; ghi mới
///   (`writeSource`) luôn ra file mới.
///
/// **Nonisolated, an toàn đa luồng**: mọi hàm là static thuần trên file; ghi luôn atomic (file mới có thể là hard link
/// tới `source.json` cũ cho tới khi lượt dọn xoá thư mục cũ — ghi tại chỗ sẽ sửa cả bản cũ). Thao tác ghi của app đi qua
/// `fileQueue` (tuần tự) nên hai lần vá liên tiếp trên cùng nguồn giữ đúng thứ tự; đọc gọi được từ thread bất kỳ.
public enum LegadoSourceStore {
    public static let sourceFileName = ExtensionPackageReader.legadoSourceFileName

    /// Hàng đợi tuần tự cho mọi thao tác file do app khởi xướng (nhập, vá `enabled`, xoá, nạp danh sách).
    static let fileQueue = DispatchQueue(label: "TangCongCac.LegadoSourceStore", qos: .userInitiated)

    /// `extensions/legado/<packageId>.json` — không tạo thư mục. `nil` khi `packageId` không làm được tên file.
    public static func fileURL(packageId: String) -> URL? {
        ExtensionFolderLocator.legadoPackageURL(packageId: packageId)
    }

    /// Vị trí của nguồn theo bản ghi trong kho tiện ích (file mới hoặc thư mục cũ); không có bản ghi ⇒ file mới.
    public static func location(packageId: String) -> URL? {
        if let ext = ExtensionLibraryRepository.snapshot(packageId: packageId), !ext.localPath.isEmpty {
            return URL(fileURLWithPath: ext.localPath)
        }
        return fileURL(packageId: packageId)
    }

    // MARK: - Đọc

    /// Đọc nguồn ở `localPath` (= `Extension.localPath` của bản ghi: file mới hoặc thư mục cũ).
    public static func loadSource(localPath: String) throws -> LegadoBookSource {
        let trimmed = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LegadoSourceError.notFound(localPath) }
        let data = try readSourceData(at: URL(fileURLWithPath: trimmed))
        do {
            return try LegadoBookSource(data: data)
        } catch {
            throw LegadoSourceError.invalidJSON
        }
    }

    /// Đọc theo `packageId` qua bảng chụp kho tiện ích, dự phòng `extensions/legado/<packageId>.json`.
    public static func loadSource(packageId: String) throws -> LegadoBookSource {
        guard let url = location(packageId: packageId) else { throw LegadoSourceError.notFound(packageId) }
        return try loadSource(localPath: url.path)
    }

    /// Bytes nguồn ở `location` (file mới, hoặc `source.json` trong thư mục cũ).
    static func readSourceData(at location: URL) throws -> Data {
        let url = sourceFileURL(at: location)
        try validatePathSafety(for: url)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw LegadoSourceError.fileRead("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// File chứa nguồn: chính `location` khi là file `.json`; thư mục cũ ⇒ `<location>/source.json`.
    /// Rẽ theo đuôi `.json`, không theo `hasDirectoryPath`.
    static func sourceFileURL(at location: URL) -> URL {
        if location.pathExtension.lowercased() == ExtensionFolderLocator.packageFileExtension {
            return location
        }
        return location.appendingPathComponent(sourceFileName)
    }

    // MARK: - Ghi

    /// Ghi `extensions/legado/<packageId>.json` (bytes `sourceJSON`, atomic). Trả URL file đã ghi.
    @discardableResult
    static func writeSource(sourceJSON: Data, packageId: String) throws -> URL {
        guard let url = fileURL(packageId: packageId) else { throw LegadoSourceError.unsafePath }
        try validatePathSafety(for: url)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sourceJSON.write(to: url, options: [.atomic])
        } catch {
            throw LegadoSourceError.fileWrite(error.localizedDescription)
        }
        return url
    }

    /// Thêm `group` vào `bookSourceGroup` (tách theo `LegadoBookSource.splitGroups`, nối lại bằng `,`), giữ mọi khoá
    /// khác. Không đổi `version` (nhóm là nhãn người dùng, như bật/tắt). `false` khi đã có nhóm đó.
    @discardableResult
    static func addGroup(_ group: String, at location: URL) throws -> Bool {
        try patch(at: location) { object in
            var groups = LegadoBookSource.splitGroups(LegadoModelCoercion.string(object["bookSourceGroup"]) ?? "")
            guard !groups.contains(group) else { return false }
            groups.append(group)
            object["bookSourceGroup"] = groups.joined(separator: ",")
            return true
        }
    }

    /// Vá **đúng khoá `enabled`** của nguồn, giữ nguyên mọi khoá khác. Không đổi `version` (bật/tắt là trạng thái người
    /// dùng, như ghim). Trả `false` khi giá trị đã đúng (không ghi).
    @discardableResult
    static func setEnabled(_ enabled: Bool, at location: URL) throws -> Bool {
        try patch(at: location) { object in
            if LegadoModelCoercion.bool(object["enabled"]) == enabled, object["enabled"] is NSNumber { return false }
            object["enabled"] = NSNumber(value: enabled)
            return true
        }
    }

    /// Đọc object nguồn ở `location`, cho `body` sửa (trả `false` = không đổi), rồi ghi lại atomic đúng chỗ đã đọc.
    private static func patch(at location: URL, _ body: (inout [String: Any]) -> Bool) throws -> Bool {
        let data = try readSourceData(at: location)
        guard var object = LegadoModelJSON.parseDocument(data: data) as? [String: Any] else {
            throw LegadoSourceError.invalidJSON
        }
        guard body(&object) else { return false }
        guard let patched = LegadoModelJSON.serialize(object) else { throw LegadoSourceError.invalidJSON }
        let url = sourceFileURL(at: location)
        try validatePathSafety(for: url)
        do {
            try patched.write(to: url, options: [.atomic])
        } catch {
            throw LegadoSourceError.fileWrite(error.localizedDescription)
        }
        return true
    }

    /// Xoá nguồn ở `location` (file mới hoặc cả thư mục cũ). Không tồn tại ⇒ thành công.
    static func remove(at location: URL) throws {
        try validatePathSafety(for: location)
        guard FileManager.default.fileExists(atPath: location.path) else { return }
        do {
            try FileManager.default.removeItem(at: location)
        } catch {
            throw LegadoSourceError.fileWrite(error.localizedDescription)
        }
    }

    // MARK: - Bản ghi kho tiện ích

    /// Cờ 18+ của nguồn — **một** công thức cho `makeCommand` lẫn bước sửa cờ của `LegadoSourceRepository`
    /// (khác đầu vào là hai nơi sửa qua sửa lại mãi).
    static func isNsfw(_ source: LegadoBookSource) -> Bool {
        ExtensionNsfwClassifier.isLegadoNsfw(
            name: source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines),
            groups: source.groups,
            sourceUrl: source.trimmedSourceUrl
        )
    }

    /// Command upsert của một nguồn đã ghi file (`localPath` = vị trí đó). `desc` luôn có giá trị (kể cả `""`) để xoá
    /// ghi chú cũ khi nguồn bỏ ghi chú. Mang cờ 18+ đã tính (`declaredNsfw`).
    static func makeCommand(source: LegadoBookSource, packageId: String, version: Int, location: URL) -> UpsertExtensionCommand? {
        guard let type = source.kind.extensionType else { return nil }
        return UpsertExtensionCommand(
            packageId: packageId,
            name: source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines),
            author: LegadoSourceIdentity.author,
            version: version,
            remoteVersion: nil,
            sourceUrl: source.trimmedSourceUrl,
            iconUrl: nil,
            desc: source.bookSourceComment,
            type: type,
            locale: LegadoSourceIdentity.locale,
            localPath: location.path,
            downloadUrl: "",
            configJson: nil,
            repositoryUrl: nil,
            installOrigin: LegadoSourceIdentity.installOrigin,
            declaredNsfw: isNsfw(source)
        )
    }

    /// Dựng lại command từ nguồn **đang có trên đĩa** (khôi phục backup): nội dung + loại từ chính nguồn, `version` do
    /// caller đưa (bản ghi trong backup khi bản backup thay vào, bản ghi máy này khi giữ bản của máy). `nil` khi hỏng.
    static func restoreCommand(location: URL, packageId: String, version: Int) -> UpsertExtensionCommand? {
        guard let data = try? readSourceData(at: location),
              let source = try? LegadoBookSource(data: data) else { return nil }
        return makeCommand(source: source, packageId: packageId, version: version, location: location)
    }

    // MARK: - An toàn đường dẫn

    /// Đường dẫn phải nằm **trong** `extensions/` (sau khi chuẩn hoá `.`/`..`), không phải chính gốc. Không resolve
    /// symlink: file mới chưa tồn tại sẽ lệch tiền tố `/private` với gốc (cùng cách `ExtensionStorePaths`).
    static func validatePathSafety(for targetURL: URL) throws {
        let root = ExtensionFolderLocator.extensionsRoot.standardizedFileURL
        let target = targetURL.standardizedFileURL
        guard target.pathComponents.count > root.pathComponents.count,
              target.pathComponents.starts(with: root.pathComponents) else {
            throw LegadoSourceError.unsafePath
        }
    }
}
