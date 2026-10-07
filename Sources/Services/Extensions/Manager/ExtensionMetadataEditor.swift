import Foundation

/// Đọc/ghi khối `metadata` của `plugin.json` cho màn Cấu hình tiện ích.
///
/// ## Một cửa duy nhất cho phần file
/// `metadata` là dữ liệu nằm **trên đĩa**: app chỉ có cột DB cho `name`, `author`, `version`, `source`,
/// `icon`, `description`, `type`, `locale` — còn `regexp` và `language` **không** có cột nào (và cố ý không
/// thêm, vì repo không có `VersionedSchema` nên đổi shape `@Model` là việc nguy hiểm). Mọi thao tác đọc/ghi
/// file của màn cấu hình đi qua đây để luật "đọc ở đâu thì ghi ở đó" chỉ có một định nghĩa.
///
/// ## Ghi phải MERGE, tuyệt đối không ghi đè cả file
/// `plugin.json` còn chứa `config` — nguồn mặc định cho `getCombinedConfigs` — và các khoá trỏ tới file
/// script. Ghi lại cả file bằng một dict mới là xoá sạch chúng, tức hỏng cấu hình và hỏng cả tiện ích. Ở đây
/// chỉ **sửa đúng những khoá được truyền vào** rồi ghi `.atomic`.
///
/// Hệ quả đã biết: `JSONSerialization` ghi lại file với thứ tự khoá sắp xếp (`sortedKeys`) và thụt lề đều, nên
/// `plugin.json` bị **định dạng lại** sau lần sửa đầu tiên. Nội dung vẫn tương đương về ngữ nghĩa; đây là giá
/// của việc không tự vá chuỗi JSON bằng tay.
///
/// ## `metadata` có thể **không tồn tại**
/// Bốn chỗ đọc trong app dùng cùng một luật `json["metadata"] ?? json`:
/// `ExtensionManager.installFromLocalZip:199`, `ExtensionDraftMetadata.read:81`,
/// `ExtensionSyncCommandBuilder.parse:154`, `TranslationConfigStore:153`. Lúc ghi phải theo **đúng** luật đó:
/// file phẳng thì sửa ở gốc và **không** sinh thêm object `metadata` mới — nếu không, bốn reader kia vẫn đọc
/// ở gốc và không thấy gì đổi.
enum ExtensionMetadataEditor {
    /// Sáu khoá màn cấu hình cho sửa.
    static let editableKeys = ["name", "source", "regexp", "description", "locale", "type"]
    /// Ba khoá chỉ đọc (hiện để biết, không ghi).
    static let readOnlyKeys = ["author", "version", "language"]

    /// Chín trường của `metadata`, đã chuẩn hoá về chuỗi để View vẽ thẳng.
    struct Metadata: Equatable {
        var name = ""
        var author = ""
        var version = ""
        var source = ""
        var regexp = ""
        var description = ""
        var locale = ""
        var type = ""
        var language = ""
    }

    enum EditorError: LocalizedError {
        case missingPluginJson
        case invalidPluginJson
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingPluginJson: return "Không tìm thấy tệp plugin.json của tiện ích"
            case .invalidPluginJson: return "plugin.json không phải JSON hợp lệ"
            case .writeFailed(let message): return "Không ghi được plugin.json: \(message)"
            }
        }
    }

    static func pluginJsonURL(localPath: String) -> URL {
        URL(fileURLWithPath: localPath).appendingPathComponent("plugin.json")
    }

    /// Đọc 9 trường. `version` có thể là số hoặc chuỗi trong file nên được ép về chuỗi.
    static func read(localPath: String) throws -> Metadata {
        guard let data = try? Data(contentsOf: pluginJsonURL(localPath: localPath)) else {
            throw EditorError.missingPluginJson
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw EditorError.invalidPluginJson
        }
        let meta = (json["metadata"] as? [String: Any]) ?? json

        var result = Metadata()
        result.name = meta["name"] as? String ?? ""
        result.author = meta["author"] as? String ?? ""
        if let intVersion = meta["version"] as? Int {
            result.version = "\(intVersion)"
        } else if let textVersion = meta["version"] as? String {
            result.version = textVersion
        }
        result.source = meta["source"] as? String ?? ""
        result.regexp = meta["regexp"] as? String ?? ""
        result.description = meta["description"] as? String ?? ""
        result.locale = (meta["locale"] as? String) ?? (meta["language"] as? String) ?? ""
        result.type = meta["type"] as? String ?? ""
        result.language = meta["language"] as? String ?? ""
        return result
    }

    /// Ghi các khoá trong `changes` vào khối `metadata`; trả về **danh sách khoá đã đổi thật**.
    ///
    /// Khoá không nằm trong `editableKeys` bị bỏ qua — đây là chốt chặn thứ hai sau tầng View, để một lần gọi
    /// sai không ghi được `author`/`version`/`language` (ba trường chỉ đọc).
    @discardableResult
    static func write(changes: [String: String], localPath: String) throws -> [String] {
        let url = pluginJsonURL(localPath: localPath)
        guard let data = try? Data(contentsOf: url) else {
            throw EditorError.missingPluginJson
        }
        guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw EditorError.invalidPluginJson
        }

        let hasMetadataBlock = json["metadata"] is [String: Any]
        var block = (json["metadata"] as? [String: Any]) ?? json

        var changed: [String] = []
        for key in editableKeys {
            guard let newValue = changes[key] else { continue }
            if (block[key] as? String) == newValue { continue }
            block[key] = newValue
            changed.append(key)
        }
        guard !changed.isEmpty else { return [] }

        if hasMetadataBlock {
            json["metadata"] = block
        } else {
            json = block
        }

        guard let output = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            throw EditorError.invalidPluginJson
        }
        do {
            try output.write(to: url, options: .atomic)
        } catch {
            throw EditorError.writeFailed(error.localizedDescription)
        }
        return changed
    }
}
