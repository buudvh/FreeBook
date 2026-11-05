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
            let pluginJsonUrl = URL(fileURLWithPath: localPath).appendingPathComponent("plugin.json")
            guard let data = try? Data(contentsOf: pluginJsonUrl),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = (json["script"] as? [String: Any])?[key] as? String else { return nil }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
