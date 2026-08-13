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

    public init(
        packageId: String,
        name: String,
        author: String = "",
        version: Int = 1,
        remoteVersion: Int? = nil,
        sourceUrl: String = "",
        iconUrl: String? = nil,
        desc: String? = nil,
        type: String = "novel",
        locale: String = "vi_VN",
        localPath: String? = nil,
        downloadUrl: String = "",
        configJson: String? = nil,
        repositoryUrl: String? = nil
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
    }
}
