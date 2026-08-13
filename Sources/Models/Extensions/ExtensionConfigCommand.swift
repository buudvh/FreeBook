import Foundation

public struct ExtensionConfigCommand: Sendable {
    public let packageId: String
    public let configJson: String

    public init(packageId: String, configJson: String) {
        self.packageId = packageId
        self.configJson = configJson
    }
}
