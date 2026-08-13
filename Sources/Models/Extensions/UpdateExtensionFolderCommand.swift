import Foundation

public struct UpdateExtensionFolderCommand: Sendable {
    public let packageId: String
    public let localFolder: String

    public init(packageId: String, localFolder: String) {
        self.packageId = packageId
        self.localFolder = localFolder
    }
}
