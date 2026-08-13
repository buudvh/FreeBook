import Foundation

public struct ExtensionExecutionSnapshot: Sendable {
    public let packageId: String
    public let name: String
    public let localPath: String
    public let downloadUrl: String
    public let configJson: String

    public init(
        packageId: String,
        name: String,
        localPath: String,
        downloadUrl: String,
        configJson: String
    ) {
        self.packageId = packageId
        self.name = name
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        self.configJson = configJson
    }
}
