import Foundation

/// Lưu trữ file của nguồn Legado: mỗi nguồn là thư mục `applicationSupport/extensions/<packageId>/` gồm
///
/// - `source.json` — object JSON gốc của nguồn, **giữ mọi khoá** (bytes JSON ổn định: khoá sắp xếp);
/// - `plugin.json` — **sinh tự động** `{"metadata": {name, author: "Legado", version, source, type, locale: "zh_CN",
///   description, nsfw}}` (`nsfw` theo `ExtensionNsfwClassifier.isLegadoNsfw`). Bắt buộc phải có: `ExtensionTransactionCoordinator` chỉ nhận thư mục có `plugin.json`, và audit
///   khi mở màn Kho xoá bản ghi có thư mục thiếu nó. Không có khoá `script` ⇒ mọi đường chạy JS báo lỗi rõ ràng.
///
/// **Nonisolated, an toàn đa luồng**: mọi hàm là static thuần trên file. Ghi `source.json` trước, `plugin.json` sau
/// (thư mục chỉ "tồn tại" khi có `plugin.json`); ghi atomic. Thao tác ghi của app đi qua `fileQueue` (tuần tự) nên
/// hai lần vá liên tiếp trên cùng nguồn giữ đúng thứ tự; đọc gọi được từ thread bất kỳ.
public enum LegadoSourceStore {
    public static let sourceFileName = "source.json"
    public static let manifestFileName = "plugin.json"

    /// Hàng đợi tuần tự cho mọi thao tác file do app khởi xướng (nhập, vá `enabled`, xoá, nạp danh sách).
    static let fileQueue = DispatchQueue(label: "FreeBook.LegadoSourceStore", qos: .userInitiated)

    /// `extensions/<packageId>/` — không tạo thư mục.
    public static func directoryURL(packageId: String) -> URL {
        ExtensionFolderLocator.extensionsRoot.appendingPathComponent(packageId, isDirectory: true)
    }

    // MARK: - Đọc

    /// Đọc `source.json` trong thư mục `localPath` (= `Extension.localPath` của bản ghi).
    public static func loadSource(localPath: String) throws -> LegadoBookSource {
        let trimmed = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LegadoSourceError.notFound(localPath) }
        let data = try readSourceData(directory: URL(fileURLWithPath: trimmed, isDirectory: true))
        do {
            return try LegadoBookSource(data: data)
        } catch {
            throw LegadoSourceError.invalidJSON
        }
    }

    /// Đọc theo `packageId` qua bảng chụp kho tiện ích (thư mục tương đối của bản ghi), dự phòng `extensions/<packageId>/`.
    public static func loadSource(packageId: String) throws -> LegadoBookSource {
        if let ext = ExtensionLibraryRepository.snapshot(packageId: packageId), !ext.localPath.isEmpty {
            return try loadSource(localPath: ext.localPath)
        }
        return try loadSource(localPath: directoryURL(packageId: packageId).path)
    }

    static func readSourceData(directory: URL) throws -> Data {
        let url = directory.appendingPathComponent(sourceFileName)
        try validatePathSafety(for: url)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw LegadoSourceError.fileRead("\(sourceFileName): \(error.localizedDescription)")
        }
    }

    /// `metadata` của `plugin.json`; `nil` khi thiếu file / hỏng.
    static func manifestMetadata(directory: URL) -> [String: Any]? {
        let url = directory.appendingPathComponent(manifestFileName)
        guard (try? validatePathSafety(for: url)) != nil,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["metadata"] as? [String: Any] ?? json
    }

    static func manifestVersion(directory: URL) -> Int? {
        guard let metadata = manifestMetadata(directory: directory) else { return nil }
        return LegadoModelCoercion.int(metadata["version"])
    }

    // MARK: - Ghi

    /// Ghi `source.json` (bytes `sourceJSON`) rồi `plugin.json`. Trả thư mục đã ghi.
    @discardableResult
    static func writeSource(
        sourceJSON: Data,
        source: LegadoBookSource,
        packageId: String,
        version: Int
    ) throws -> URL {
        let directory = directoryURL(packageId: packageId)
        try validatePathSafety(for: directory)
        let manifest = try manifestData(source: source, version: version)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try sourceJSON.write(to: directory.appendingPathComponent(sourceFileName), options: [.atomic])
            try manifest.write(to: directory.appendingPathComponent(manifestFileName), options: [.atomic])
        } catch {
            throw LegadoSourceError.fileWrite(error.localizedDescription)
        }
        return directory
    }

    /// Bytes `plugin.json` sinh tự động. `nsfw` luôn ghi (Bool): `ExtensionTransactionCoordinator` đọc nó thành
    /// `Extension.isNsfw` lúc upsert, nên Tìm kiếm/Khám phá/lịch sử thấy nguồn 18+ mà không cần đọc nhóm.
    static func manifestData(source: LegadoBookSource, version: Int) throws -> Data {
        guard let type = source.kind.extensionType else { throw LegadoSourceError.invalidJSON }
        let isNsfw = ExtensionNsfwClassifier.isLegadoNsfw(
            name: source.bookSourceName, groups: source.groups, sourceUrl: source.trimmedSourceUrl
        )
        let metadata: [String: Any] = [
            "name": source.bookSourceName,
            "author": LegadoSourceIdentity.author,
            "version": version,
            "source": source.bookSourceUrl,
            "type": type,
            "locale": LegadoSourceIdentity.locale,
            "description": source.bookSourceComment,
            "nsfw": NSNumber(value: isNsfw)
        ]
        guard let manifest = LegadoModelJSON.serialize(["metadata": metadata]) else {
            throw LegadoSourceError.fileWrite(manifestFileName)
        }
        return manifest
    }

    /// `plugin.json` đã có cờ `nsfw` chưa (nguồn nhập trước khi kho ghi cờ này thì chưa).
    static func manifestHasNsfwFlag(directory: URL) -> Bool {
        manifestMetadata(directory: directory)?["nsfw"] != nil
    }

    /// Ghi lại **chỉ** `plugin.json` (cùng `version`) — bù cờ `nsfw` cho nguồn nhập trước đó.
    static func rewriteManifest(source: LegadoBookSource, version: Int, directory: URL) throws {
        let url = directory.appendingPathComponent(manifestFileName)
        try validatePathSafety(for: url)
        let manifest = try manifestData(source: source, version: version)
        do {
            try manifest.write(to: url, options: [.atomic])
        } catch {
            throw LegadoSourceError.fileWrite(error.localizedDescription)
        }
    }

    /// Thêm `group` vào `bookSourceGroup` (tách theo `LegadoBookSource.splitGroups`, nối lại bằng `,`), giữ mọi khoá
    /// khác. Không đổi `plugin.json`/`version` (nhóm là nhãn người dùng, như bật/tắt). `false` khi đã có nhóm đó.
    @discardableResult
    static func addGroup(_ group: String, directory: URL) throws -> Bool {
        let data = try readSourceData(directory: directory)
        guard var object = LegadoModelJSON.parseDocument(data: data) as? [String: Any] else {
            throw LegadoSourceError.invalidJSON
        }
        var groups = LegadoBookSource.splitGroups(LegadoModelCoercion.string(object["bookSourceGroup"]) ?? "")
        guard !groups.contains(group) else { return false }
        groups.append(group)
        object["bookSourceGroup"] = groups.joined(separator: ",")
        guard let patched = LegadoModelJSON.serialize(object) else { throw LegadoSourceError.invalidJSON }
        let url = directory.appendingPathComponent(sourceFileName)
        try validatePathSafety(for: url)
        do {
            try patched.write(to: url, options: [.atomic])
        } catch {
            throw LegadoSourceError.fileWrite(error.localizedDescription)
        }
        return true
    }

    /// Vá **đúng khoá `enabled`** của `source.json`, giữ nguyên mọi khoá khác. Không đổi `plugin.json`/`version`
    /// (bật/tắt là trạng thái người dùng, như ghim). Trả `false` khi giá trị đã đúng (không ghi).
    @discardableResult
    static func setEnabled(_ enabled: Bool, directory: URL) throws -> Bool {
        let data = try readSourceData(directory: directory)
        guard var object = LegadoModelJSON.parseDocument(data: data) as? [String: Any] else {
            throw LegadoSourceError.invalidJSON
        }
        if LegadoModelCoercion.bool(object["enabled"]) == enabled, object["enabled"] is NSNumber { return false }
        object["enabled"] = NSNumber(value: enabled)
        guard let patched = LegadoModelJSON.serialize(object) else { throw LegadoSourceError.invalidJSON }
        let url = directory.appendingPathComponent(sourceFileName)
        try validatePathSafety(for: url)
        do {
            try patched.write(to: url, options: [.atomic])
        } catch {
            throw LegadoSourceError.fileWrite(error.localizedDescription)
        }
        return true
    }

    /// Xoá cả thư mục nguồn. Thư mục không tồn tại ⇒ thành công.
    static func removeDirectory(_ directory: URL) throws {
        try validatePathSafety(for: directory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw LegadoSourceError.fileWrite(error.localizedDescription)
        }
    }

    // MARK: - Bản ghi kho tiện ích

    /// Command upsert của một nguồn đã ghi file. `desc` luôn có giá trị (kể cả `""`) để xoá ghi chú cũ khi nguồn bỏ ghi chú.
    static func makeCommand(source: LegadoBookSource, packageId: String, version: Int, directory: URL) -> UpsertExtensionCommand? {
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
            localPath: directory.path,
            downloadUrl: "",
            configJson: nil,
            repositoryUrl: nil,
            installOrigin: LegadoSourceIdentity.installOrigin
        )
    }

    /// Dựng lại command từ thư mục **đang có trên đĩa** (khôi phục backup): nội dung từ `source.json`, `version` và
    /// `type` từ `plugin.json` (dự phòng: loại suy từ `source.json`, version 1). `nil` khi thư mục hỏng.
    static func restoreCommand(directory: URL, packageId: String) -> UpsertExtensionCommand? {
        guard let data = try? readSourceData(directory: directory),
              let source = try? LegadoBookSource(data: data),
              var command = makeCommand(
                source: source,
                packageId: packageId,
                version: manifestVersion(directory: directory) ?? 1,
                directory: directory
              ) else { return nil }
        if let manifestType = manifestMetadata(directory: directory)?["type"] as? String,
           LegadoSourceKind(extensionType: manifestType) != nil, manifestType != command.type {
            command = UpsertExtensionCommand(
                packageId: command.packageId, name: command.name, author: command.author,
                version: command.version, remoteVersion: nil, sourceUrl: command.sourceUrl, iconUrl: nil,
                desc: command.desc, type: manifestType, locale: command.locale, localPath: command.localPath,
                downloadUrl: "", configJson: nil, repositoryUrl: nil, installOrigin: command.installOrigin
            )
        }
        return command
    }

    // MARK: - An toàn đường dẫn

    /// Đường dẫn phải nằm **trong** `extensions/` (sau khi chuẩn hoá `.`/`..`), không phải chính gốc. Không resolve
    /// symlink: thư mục mới chưa tồn tại sẽ lệch tiền tố `/private` với gốc (cùng cách `ExtensionStorePaths`).
    static func validatePathSafety(for targetURL: URL) throws {
        let root = ExtensionFolderLocator.extensionsRoot.standardizedFileURL
        let target = targetURL.standardizedFileURL
        guard target.pathComponents.count > root.pathComponents.count,
              target.pathComponents.starts(with: root.pathComponents) else {
            throw LegadoSourceError.unsafePath
        }
    }
}
