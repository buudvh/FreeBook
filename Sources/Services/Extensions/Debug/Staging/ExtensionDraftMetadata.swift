import Foundation

/// Metadata đọc từ `plugin.json` của một bản nháp — đủ để dựng hàng `Extension` trong SwiftData khi
/// cài **mới** một extension chưa có trên app (Phase 5).
///
/// Luật đọc khớp **từng bước** với `ExtensionManager.installFromLocalZip`: lấy mục `metadata` nếu có,
/// không thì chính object gốc; `packageId` tường minh thắng, thiếu thì `name.lowercased()` thay dấu
/// cách bằng `_`. Cố ý nhân bản luật đó ở đây chứ không gọi lại đường zip: đường zip **di chuyển** thư
/// mục nguồn và tự quyết định thư mục đích, còn ở đây nguồn là staging và phải giữ nguyên để
/// `run.start` với `sourceMode: "draft"` còn dùng được sau khi cài.
///
/// `packageId` **không** lấy từ client: client chỉ suy từ tên thư mục/`metadata.name`, còn app là
/// thẩm quyền cuối cùng về danh tính. Nhờ vậy nếu client gửi `Truyen Full` mà app đang có
/// `truyen_full` thì lệnh install được nhận diện là **cập nhật**, không tạo bản ghi trùng.
public struct ExtensionDraftMetadata: Sendable, Equatable {
    public enum MetadataError: LocalizedError {
        case missingPluginJson
        case invalidPluginJson
        case emptyName
        case unsafePackageId(String)

        public var errorDescription: String? {
            switch self {
            case .missingPluginJson: return "Bản nháp không có plugin.json ở gốc"
            case .invalidPluginJson: return "plugin.json của bản nháp không phải JSON hợp lệ"
            case .emptyName: return "plugin.json không khai `name` nên không suy được packageId"
            case .unsafePackageId(let reason): return "packageId suy từ plugin.json không an toàn: \(reason)"
            }
        }
    }

    public let packageId: String
    public let name: String
    public let author: String
    public let version: Int
    public let type: String
    public let locale: String
    public let sourceUrl: String
    public let iconUrl: String?
    public let desc: String?

    public init(
        packageId: String,
        name: String,
        author: String,
        version: Int,
        type: String,
        locale: String,
        sourceUrl: String,
        iconUrl: String?,
        desc: String?
    ) {
        self.packageId = packageId
        self.name = name
        self.author = author
        self.version = version
        self.type = type
        self.locale = locale
        self.sourceUrl = sourceUrl
        self.iconUrl = iconUrl
        self.desc = desc
    }

    /// Mirror của `ExtensionSyncCommandBuilder.packageId(forName:)` và của nhánh không có `packageId`
    /// trong `installFromLocalZip`. Ba đường cài phải cho ra **cùng một** id với cùng một cái tên,
    /// nếu không thư viện sẽ có hai hàng cho một extension.
    public static func slug(forName name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func read(from directory: URL) throws -> ExtensionDraftMetadata {
        let pluginUrl = directory.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: pluginUrl) else {
            throw MetadataError.missingPluginJson
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MetadataError.invalidPluginJson
        }
        let meta = json["metadata"] as? [String: Any] ?? json

        let name = ((meta["name"] as? String) ?? (json["name"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPackageId = (meta["packageId"] as? String) ?? (json["packageId"] as? String) ?? ""
        let packageId = rawPackageId.isEmpty ? Self.slug(forName: name) : rawPackageId
        guard !packageId.isEmpty else { throw MetadataError.emptyName }
        if let reason = ExtensionDraftManifest.pathIssue(packageId) {
            throw MetadataError.unsafePackageId(reason)
        }

        var version = 1
        if let value = meta["version"] as? Int {
            version = value
        } else if let text = meta["version"] as? String, let value = Int(text) {
            version = value
        }

        return ExtensionDraftMetadata(
            packageId: packageId,
            name: name.isEmpty ? packageId : name,
            author: (meta["author"] as? String) ?? "",
            version: version,
            type: (meta["type"] as? String) ?? ExtensionType.novel,
            locale: (meta["locale"] as? String) ?? (meta["language"] as? String) ?? "vi_VN",
            sourceUrl: (meta["source"] as? String) ?? "",
            iconUrl: meta["icon"] as? String,
            desc: meta["description"] as? String
        )
    }

    /// Command để `ExtensionTransactionCoordinator` upsert hàng `Extension`.
    ///
    /// `downloadUrl` và `repositoryUrl` cố ý để rỗng/`nil`: bản này đến từ máy phát triển, không thuộc
    /// kho nào — nếu gán một kho thì lượt đồng bộ kho sau đó sẽ coi nó là bản lạc và có thể prune bản ghi.
    /// `configJson: nil` để coordinator đặt `"{}"` cho hàng mới và **không** ghi đè config người dùng đã
    /// lưu ở hàng cũ.
    public func upsertCommand(localPath: String) -> UpsertExtensionCommand {
        UpsertExtensionCommand(
            packageId: packageId,
            name: name,
            author: author,
            version: version,
            remoteVersion: nil,
            sourceUrl: sourceUrl,
            iconUrl: iconUrl,
            desc: desc,
            type: type,
            locale: locale,
            localPath: localPath,
            downloadUrl: "",
            configJson: nil,
            repositoryUrl: nil
        )
    }
}
