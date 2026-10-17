import Foundation

/// Một tiện ích JavaScript — **giá trị**, không còn là `@Model`.
///
/// Nguồn sự thật là `ExtensionLibraryRepository` (file `extension_store/installed.json`); mọi ghi đi qua
/// `ExtensionTransactionCoordinator`. Vì là struct, một `Extension` View đang giữ chỉ là **ảnh chụp**: sau khi
/// sửa phải tra lại theo `packageId`.
///
/// Danh mục tiện ích **chưa cài** (dựng từ cache registry) cũng dùng type này với `folder = ""` — giữ nguyên
/// luật `localPath.isEmpty` = chưa cài mà View đang dùng.
public struct Extension: Codable, Identifiable, Hashable, Sendable {
    public var packageId: String // Danh tính duy nhất (tên thư mục cài / `plugin.json packageId`)
    public var name: String
    public var author: String
    public var version: Int
    public var sourceUrl: String
    public var iconUrl: String?
    public var desc: String?
    public var type: String // "novel", "chinese_novel", "comic" hoặc "tts"
    public var locale: String // "vi_VN", "zh_CN", ...
    /// Thư mục **tương đối** dưới `ExtensionFolderLocator.extensionsRoot` (vd `twkan`, `twkan/twkan`).
    /// `""` = mục catalog chưa cài.
    public var folder: String
    public var configJson: String // Cấu hình đã chỉnh sửa dạng JSON
    public var downloadUrl: String // Đường dẫn tải file zip tiện ích
    /// URL kho đã cài tiện ích này; `nil` với tiện ích import zip / cài từ Debug server.
    public var repositoryUrl: String?
    public var installOrigin: String
    public var pinnedAt: Date?
    public var lastUsedAt: Date?
    public var installedAt: Date?
    /// Lần cuối gói tiện ích được cài/cập nhật (upsert) — sửa config/metadata/ghim không đổi trường này.
    public var updatedAt: Date?
    /// Phiên bản trong registry của kho — **không lưu** (ngoài `CodingKeys`), repository gắn vào khi publish.
    public var remoteVersion: Int?
    /// Cờ nội dung người lớn **do tiện ích khai** (`metadata.nsfw` / thẻ `nsfw` trong `plugin.json` hoặc registry).
    /// `nil` = không khai — khi đó `ExtensionNsfwClassifier` đoán theo từ khoá/tên miền.
    public var isNsfw: Bool?
    /// Người dùng bật/tắt "Lưu lịch sử đọc/xem" cho tiện ích này; `nil` = theo mặc định (`!isNsfw`, xem
    /// `ExtensionHistoryPolicy`). Không nằm trong `configJson` vì `configJson` bị tiêm thành biến global của JS.
    public var savesHistory: Bool?
    /// Người dùng tự **đánh dấu** (`true`) / **bỏ đánh dấu** (`false`) NSFW; `nil` = nhận diện tự động. Thắng cả cờ
    /// tiện ích tự khai lẫn heuristic (`ExtensionNsfwClassifier`). Tách khỏi `isNsfw` vì cập nhật tiện ích đọc lại
    /// `isNsfw` từ `plugin.json` — lựa chọn của người dùng không được mất theo.
    public var nsfwOverride: Bool?

    public static let installOriginRepository = "repository"
    public static let installOriginImportZip = "importZip"
    public static let installOriginDebugServer = "debugServer"

    public var id: String { packageId }

    /// Đường dẫn tuyệt đối tính lại từ gốc của lần chạy này; `""` khi chưa cài.
    public var localPath: String { ExtensionFolderLocator.absolutePath(forFolder: folder) }

    public var isInstalled: Bool { !folder.isEmpty }

    public var hasUpdate: Bool {
        guard isInstalled, let remote = remoteVersion else { return false }
        return remote > version
    }

    public var isPinned: Bool { pinnedAt != nil }

    public var isChineseSource: Bool {
        let loc = locale.lowercased()
        let t = type.lowercased()
        return loc.contains("zh") || loc.contains("cn") || t == "chinese_novel"
    }

    public var showsDebugBadge: Bool {
        installOrigin == Self.installOriginImportZip
            || installOrigin == Self.installOriginDebugServer
            || (repositoryUrl == nil && downloadUrl.isEmpty && isInstalled)
    }

    public init(
        packageId: String,
        name: String,
        author: String = "",
        version: Int = 1,
        sourceUrl: String = "",
        iconUrl: String? = nil,
        desc: String? = nil,
        type: String = ExtensionType.novel,
        locale: String = "vi_VN",
        folder: String = "",
        configJson: String = "{}",
        downloadUrl: String = "",
        repositoryUrl: String? = nil,
        installOrigin: String = Extension.installOriginRepository,
        pinnedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        installedAt: Date? = nil,
        updatedAt: Date? = nil,
        remoteVersion: Int? = nil,
        isNsfw: Bool? = nil,
        savesHistory: Bool? = nil,
        nsfwOverride: Bool? = nil
    ) {
        self.packageId = packageId
        self.name = name
        self.author = author
        self.version = version
        self.sourceUrl = sourceUrl
        self.iconUrl = iconUrl
        self.desc = desc
        self.type = type
        self.locale = locale
        self.folder = folder
        self.configJson = configJson
        self.downloadUrl = downloadUrl
        self.repositoryUrl = repositoryUrl
        self.installOrigin = installOrigin
        self.pinnedAt = pinnedAt
        self.lastUsedAt = lastUsedAt
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.remoteVersion = remoteVersion
        self.isNsfw = isNsfw
        self.savesHistory = savesHistory
        self.nsfwOverride = nsfwOverride
    }

    // MARK: - Codable

    /// Không có `remoteVersion`: trường tính lại mỗi lần publish từ cache registry, không được ghi xuống đĩa.
    private enum CodingKeys: String, CodingKey {
        case packageId, name, author, version, sourceUrl, iconUrl, desc, type, locale, folder
        case configJson, downloadUrl, repositoryUrl, installOrigin
        case pinnedAt, lastUsedAt, installedAt, updatedAt
        case isNsfw, savesHistory, nsfwOverride
    }

    /// Decode khoan dung: chỉ `packageId` là bắt buộc, trường thiếu rơi về mặc định — file do bản app khác
    /// (cũ hơn/mới hơn) ghi vẫn đọc được thay vì làm hỏng cả `installed.json`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        packageId = try c.decode(String.self, forKey: .packageId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? packageId
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl) ?? ""
        iconUrl = try c.decodeIfPresent(String.self, forKey: .iconUrl)
        desc = try c.decodeIfPresent(String.self, forKey: .desc)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ExtensionType.novel
        locale = try c.decodeIfPresent(String.self, forKey: .locale) ?? "vi_VN"
        folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? ""
        configJson = try c.decodeIfPresent(String.self, forKey: .configJson) ?? "{}"
        downloadUrl = try c.decodeIfPresent(String.self, forKey: .downloadUrl) ?? ""
        repositoryUrl = try c.decodeIfPresent(String.self, forKey: .repositoryUrl)
        installOrigin = try c.decodeIfPresent(String.self, forKey: .installOrigin) ?? Self.installOriginRepository
        pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        installedAt = try c.decodeIfPresent(Date.self, forKey: .installedAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        remoteVersion = nil
        // Trường mới: sai kiểu ⇒ `nil` (theo mặc định), không làm hỏng cả `installed.json`.
        isNsfw = try? c.decodeIfPresent(Bool.self, forKey: .isNsfw)
        savesHistory = try? c.decodeIfPresent(Bool.self, forKey: .savesHistory)
        nsfwOverride = try? c.decodeIfPresent(Bool.self, forKey: .nsfwOverride)
    }
}
