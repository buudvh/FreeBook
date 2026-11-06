import Foundation

/// Script của tab mà nút / sheet "Bộ lọc" xét — chỉ hiện các mục `config` script đó (cùng các file nó `load`) nhắc tới
/// (`ExtensionScriptConfigScanner`).
/// - `file`: tên file script của một mục danh sách (`CategoryResult.script` của tab home, thể loại, "Xem thêm").
/// - `pluginScript`: khoá trong khối `script` của `plugin.json` (`explore`, `genre`, `search`) — đổi ra tên file lúc quét
///   (đọc `plugin.json`, ngoài main), không phải trong `body`.
enum ExtensionFilterScope: Hashable, Sendable {
    case file(String)
    case pluginScript(String)

    /// Tên file script; `nil` khi tab không có script (khoá không khai, tên rỗng) ⇒ tab không có mục lọc nào.
    func fileName(localPath: String) -> String? {
        switch self {
        case .file(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .pluginScript(let key):
            guard let name = ExtensionPackageReader.scriptFileName(forKey: key, localPath: localPath) else { return nil }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
