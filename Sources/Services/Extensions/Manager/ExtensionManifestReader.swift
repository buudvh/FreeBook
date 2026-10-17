import Foundation

/// Đọc vài trường của `<localPath>/plugin.json` mà tầng nền cần — `metadata.source` (host mặc định) và cờ
/// nội dung người lớn (`metadata.nsfw`, kiểu cũ `"tag": "nsfw"`/`tags`).
///
/// `metadata` thiếu thì dùng gốc file, giống luồng cài (`ExtensionManager.installFromLocalZip`). Đọc lỗi ⇒ `nil`,
/// không ném. Mỗi lần gọi là một lần đọc đĩa: caller gọi **một lần cho mỗi lượt chạy script**, không gọi theo dòng.
enum ExtensionManifestReader {
    nonisolated static func metadata(localPath: String) -> [String: Any]? {
        let path = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path).appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["metadata"] as? [String: Any] ?? json
    }

    /// `metadata.source` đã trim, khác rỗng.
    nonisolated static func source(localPath: String) -> String? {
        guard let source = metadata(localPath: localPath)?["source"] as? String else { return nil }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func nsfwFlag(localPath: String) -> Bool? {
        metadata(localPath: localPath).flatMap { nsfwFlag(metadata: $0) }
    }

    /// `true` khi khai `nsfw` (bool, số hoặc chuỗi `"true"`) hoặc gắn thẻ `nsfw`; `false` khi chỉ khai
    /// `nsfw: false`; `nil` khi không khai gì.
    nonisolated static func nsfwFlag(metadata: [String: Any]) -> Bool? {
        if containsNsfwTag(metadata["tag"]) || containsNsfwTag(metadata["tags"]) { return true }
        return flag(metadata["nsfw"])
    }

    nonisolated private static func flag(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.intValue != 0
        case let text as String:
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    nonisolated private static func containsNsfwTag(_ value: Any?) -> Bool {
        switch value {
        case let text as String:
            return ExtensionRegistryItem.isNsfwTag(text)
        case let list as [Any]:
            return list.contains { ($0 as? String).map(ExtensionRegistryItem.isNsfwTag) ?? false }
        default:
            return false
        }
    }
}
