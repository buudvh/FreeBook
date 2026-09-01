import Foundation

/// Bản sao bất biến của một hàng `Extension` để mang qua ranh giới isolation.
///
/// Router chạy trong actor và đọc SwiftData bằng `ModelContext` riêng; `@Model` **không** được mang ra
/// khỏi context của nó, nên mọi thứ router cần được copy vào đây một lần.
///
/// `scriptKeys` đọc từ `plugin.json` chứ không từ DB: đó là nguồn sự thật về script mà extension khai,
/// và cũng là thứ duy nhất client được biết (`extensions.list` không trả `localPath` hay `configJson`).
public struct ExtensionDebugInstalledSnapshot: Sendable, Equatable {
    public let packageId: String
    public let name: String
    public let version: Int
    public let type: String
    public let localPath: String
    public let downloadUrl: String
    public let configJson: String
    public let sourceUrl: String
    public let scriptKeys: [String]

    public init(extensionRow: Extension) {
        self.packageId = extensionRow.packageId
        self.name = extensionRow.name
        self.version = extensionRow.version
        self.type = extensionRow.type
        self.localPath = extensionRow.localPath
        self.downloadUrl = extensionRow.downloadUrl
        self.configJson = extensionRow.configJson
        self.sourceUrl = extensionRow.sourceUrl
        self.scriptKeys = Self.readScriptKeys(localPath: extensionRow.localPath)
    }

    private static func readScriptKeys(localPath: String) -> [String] {
        guard !localPath.isEmpty else { return [] }
        let pluginUrl = URL(fileURLWithPath: localPath).appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: pluginUrl),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let scripts = json["script"] as? [String: Any] else {
            return []
        }
        return scripts.keys.sorted()
    }
}
