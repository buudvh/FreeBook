import Foundation

public struct UpsertExtensionCommand: Sendable {
    public let packageId: String
    public let name: String
    public let author: String
    public let version: Int
    public let remoteVersion: Int?
    public let sourceUrl: String
    public let iconUrl: String?
    public let desc: String?
    public let type: String
    public let locale: String
    public let localPath: String?
    public let downloadUrl: String
    public let configJson: String?
    public let repositoryUrl: String?
    public let installOrigin: String?
    /// Cờ 18+ caller đã tính sẵn — nguồn Legado (`LegadoSourceStore.makeCommand`): coordinator dùng cờ này và **không**
    /// đọc manifest (nhập hàng nghìn nguồn mà mỗi lần upsert lại parse nguồn thì rất chậm). `nil` = coordinator tự đọc
    /// cờ `plugin.json` / registry như cũ.
    public let declaredNsfw: Bool?

    public init(
        packageId: String,
        name: String,
        author: String = "",
        version: Int = 1,
        remoteVersion: Int? = nil,
        sourceUrl: String = "",
        iconUrl: String? = nil,
        desc: String? = nil,
        type: String = ExtensionType.novel,
        locale: String = "vi_VN",
        localPath: String? = nil,
        downloadUrl: String = "",
        configJson: String? = nil,
        repositoryUrl: String? = nil,
        installOrigin: String? = nil,
        declaredNsfw: Bool? = nil
    ) {
        self.packageId = packageId
        self.name = name
        self.author = author
        self.version = version
        self.remoteVersion = remoteVersion
        self.sourceUrl = sourceUrl
        self.iconUrl = iconUrl
        self.desc = desc
        self.type = type
        self.locale = locale
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        self.configJson = configJson
        self.repositoryUrl = repositoryUrl
        self.installOrigin = installOrigin
        self.declaredNsfw = declaredNsfw
    }
}
