import Foundation

/// Khối `config` của `plugin.json` thành các mục cài đặt theo thứ tự hiển thị, cùng luật dựng `configJson` khi ghi.
/// Dùng chung cho màn Cấu hình tiện ích (`ExtensionConfigView`) và sheet Bộ lọc (`ExtensionFilterSheet`) để hai nơi
/// đọc/ghi cùng một kiểu giá trị.
struct ExtensionConfigSchema {
    /// Một mục của khối `config`. Dựng tay từ dict (không `JSONDecoder`): `default`/`values` viết bằng số hay bool vẫn
    /// đọc được (ép thành chuỗi) thay vì làm mất cả dòng.
    struct Item {
        let title: String?
        let subtitle: String?
        let mode: String?
        let format: String?
        let `default`: String?
        /// Lựa chọn của `mode: "select"`; rỗng với kiểu khác.
        let values: [String]

        init(title: String?, mode: String?, format: String?, default: String?) {
            self.title = title
            self.subtitle = nil
            self.mode = mode
            self.format = format
            self.default = `default`
            self.values = []
        }

        init(dictionary: [String: Any]) {
            title = dictionary["title"] as? String
            subtitle = dictionary["subtitle"] as? String
            mode = dictionary["mode"] as? String
            format = dictionary["format"] as? String
            `default` = dictionary["default"].map(ExtensionConfigValueFormatter.text)
            values = (dictionary["values"] as? [Any])?.map(ExtensionConfigValueFormatter.text) ?? []
        }

        var isToggle: Bool { format == "boolean" || mode == "toggle" }

        /// Mục hiện ở sheet Bộ lọc: chọn một (`select`), công tắc, danh sách.
        var isFilter: Bool { mode == "select" || mode == "list" || isToggle }
    }

    enum LoadError: LocalizedError {
        case notInstalled
        case missingPluginJson
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Tiện ích chưa được cài đặt cục bộ."
            case .missingPluginJson: return "Không tìm thấy tệp plugin.json"
            case .unreadable(let message): return "Lỗi xử lý file plugin.json: \(message)"
            }
        }
    }

    /// Cookie hệ thống — nằm chung `configJson` nhưng không khai trong `plugin.json`.
    static let cookieKey = "http_should_handle_cookies"
    /// Giới hạn kết nối viết dạng giá trị trần dưới `config` (hợp đồng): không phải cài đặt nên không hiện. Vẫn được
    /// tiêm vào script (`ExtensionManager.getCombinedConfigs`). Viết thành object `{ title, mode }` thì là cài đặt thường.
    static let connectionKeys: Set<String> = ["thread_num", "delay", "ignore"]
    static let supportURLKey = "support_url"
    /// Trường thô ở gốc `plugin.json` cũng hiện như cài đặt khi `config` chưa khai.
    private static let rootKeys = ["preload_size", "max_length", "required_api_key", "support_url"]

    private(set) var items: [String: Item] = [:]
    /// Khoá của `items` theo thứ tự hiển thị: thứ tự trong `config` của `plugin.json`, rồi khoá đặc biệt ở gốc.
    private(set) var keys: [String] = []
    /// Khoá khai trong `config` (không gồm khoá ở gốc).
    private(set) var declaredKeys: [String] = []
    /// `support_url` là URL http(s) ⇒ nút "Mở trang đăng nhập" (`ExtensionConfigView+SupportLink`), không phải cài đặt.
    private(set) var supportLinkURL: String?

    /// Schema rỗng — trước khi đọc `plugin.json`, hoặc file không phải JSON object.
    init() {}

    /// Khoá hiện ở sheet Bộ lọc, theo thứ tự trong `config`.
    var filterKeys: [String] {
        declaredKeys.filter { items[$0]?.isFilter == true }
    }

    /// Khoá lọc của **một tab**: chỉ những khoá mà script của tab (cùng các file nó `load`) nhắc tới, theo thứ tự trong
    /// `config` (`ExtensionScriptConfigScanner`). Tab không có script ⇒ rỗng. Đọc file ⇒ gọi ngoài main.
    func tabFilterKeys(for scope: ExtensionFilterScope, localPath: String) -> [String] {
        let keys: [String] = self.filterKeys
        guard !keys.isEmpty, let script = scope.fileName(localPath: localPath) else { return [] }
        let used = ExtensionScriptConfigScanner.referencedKeys(localPath: localPath, entryScript: script, candidates: keys)
        return keys.filter { used.contains($0) }
    }

    // MARK: - Đọc

    static func load(localPath: String) throws -> ExtensionConfigSchema {
        guard !localPath.isEmpty else { throw LoadError.notInstalled }
        let pluginJsonUrl = URL(fileURLWithPath: localPath).appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: pluginJsonUrl.path) else { throw LoadError.missingPluginJson }
        do {
            return try parse(try Data(contentsOf: pluginJsonUrl))
        } catch {
            throw LoadError.unreadable(error.localizedDescription)
        }
    }

    /// JSON hỏng ⇒ ném lỗi; JSON hợp lệ nhưng không phải object ⇒ schema rỗng (như màn Cấu hình cũ: không có mục nào,
    /// vẫn mở được).
    static func parse(_ data: Data) throws -> ExtensionConfigSchema {
        var schema = ExtensionConfigSchema()
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return schema }

        var keys: [String] = []
        if let configSection = json["config"] as? [String: Any] {
            keys = orderedConfigKeys(in: data, section: configSection)
            for key in keys {
                guard let value = configSection[key] else { continue }
                if let dict = value as? [String: Any] {
                    schema.items[key] = Item(dictionary: dict)
                } else if connectionKeys.contains(key) {
                    continue
                } else if key == supportURLKey, let link = supportLink(from: value) {
                    schema.supportLinkURL = link
                } else if let item = bareItem(key: key, value: value) {
                    schema.items[key] = item
                }
            }
        }

        for key in rootKeys where schema.items[key] == nil {
            guard let value = json[key] else { continue }
            if key == supportURLKey, let link = supportLink(from: value) {
                schema.supportLinkURL = schema.supportLinkURL ?? link
            } else if let item = bareItem(key: key, value: value) {
                schema.items[key] = item
            }
        }

        let declared = keys.filter { schema.items[$0] != nil }
        schema.declaredKeys = declared
        schema.keys = declared + rootKeys.filter { schema.items[$0] != nil && !declared.contains($0) }
        return schema
    }

    /// Giá trị trần là URL http(s) tuyệt đối có host ⇒ chuỗi đã trim; khác ⇒ `nil`.
    static func supportLink(from value: Any) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), ExtensionCookieSync.host(of: url) != nil else { return nil }
        return text
    }

    private static func bareItem(key: String, value: Any) -> Item? {
        if let bVal = value as? Bool {
            return Item(title: key, mode: "toggle", format: "boolean", default: "\(bVal)")
        } else if let nVal = value as? NSNumber {
            return Item(title: key, mode: "input", format: "number", default: "\(nVal)")
        } else if let sVal = value as? String {
            return Item(title: key, mode: "input", format: "text", default: sVal)
        }
        return nil
    }

    /// Khoá của khối `config` theo thứ tự trong file — `JSONSerialization` trả dict mất thứ tự, nên đọc lại bằng parser
    /// JSON giữ thứ tự sẵn có của engine Legado. Không đọc được ⇒ xếp ABC như trước. Tiện ích mã hoá cài trước 1.3.672
    /// đã bị ghi lại `plugin.json` theo ABC (`ExtensionScriptDecoder`) — phải cài lại mới có thứ tự gốc.
    private static func orderedConfigKeys(in data: Data, section: [String: Any]) -> [String] {
        let sorted = section.keys.sorted()
        guard let text = String(data: data, encoding: .utf8),
              let entries = LegadoEngineJSONParser.parse(text)?["config"]?.objectEntries else { return sorted }
        var seen = Set<String>()
        let ordered = entries.map { $0.key }.filter { section[$0] != nil && seen.insert($0).inserted }
        return ordered + sorted.filter { !seen.contains($0) }
    }

    // MARK: - Giá trị

    /// Giá trị người dùng đã lưu (dạng chữ) + mặc định cho khoá chưa lưu + cookie mặc định bật. Bỏ giá trị cũ của khoá
    /// kết nối đã ẩn (bản cũ của màn Cấu hình cho sửa): lượt ghi kế tiếp xoá nó, script về giá trị của `plugin.json`.
    func initialValues(configJson: String) -> [String: String] {
        var values: [String: String] = [:]
        if let data = configJson.data(using: .utf8),
           let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (key, value) in saved where !(Self.connectionKeys.contains(key) && items[key] == nil) {
                values[key] = ExtensionConfigValueFormatter.text(value)
            }
        }
        for (key, item) in items where values[key] == nil {
            values[key] = item.default ?? ""
        }
        if values[Self.cookieKey] == nil {
            values[Self.cookieKey] = "true"
        }
        return values
    }

    /// Mục lọc nào (trong `keys` — khoá lọc của tab đang xem) đang khác mặc định — chấm trên nút lọc. Giá trị lạ của
    /// `select` coi như lựa chọn đầu (cách màn Cấu hình hiển thị).
    func hasActiveFilter(values: [String: String], keys: [String]) -> Bool {
        keys.contains { key in
            guard let item = items[key] else { return false }
            let value = values[key] ?? item.default ?? ""
            if item.mode == "select" {
                return Self.displayedSelection(value, item: item) != Self.displayedSelection(item.default, item: item)
            }
            return value != (item.default ?? "")
        }
    }

    /// Hợp đồng: giá trị không nằm trong `values` hiện lựa chọn đầu. Chỉ là hiển thị — không tự ghi đè, script vẫn nhận
    /// giá trị đã lưu cho tới khi người dùng chọn.
    static func displayedSelection(_ value: String?, item: Item) -> String {
        if let value, item.values.contains(value) { return value }
        return item.values.first ?? value ?? ""
    }

    /// Dựng `configJson` — giữ nguyên luật của nút "Lưu" cũ: bỏ giá trị rỗng, cookie luôn là bool, `boolean` ⇒ bool,
    /// `number` ⇒ Int/Double (không parse được thì giữ chuỗi), còn lại là chuỗi. `select`/`list` luôn là chuỗi dù
    /// `format` ghi gì. (Script nhận chuỗi bất kể kiểu lưu — `JSExecutor.injectGlobals`.)
    func configJsonString(from values: [String: String]) throws -> String? {
        var typedDict: [String: Any] = [:]
        for (key, strVal) in values {
            guard !strVal.isEmpty else { continue }
            if key == Self.cookieKey {
                typedDict[key] = (strVal.lowercased() == "true")
                continue
            }
            if let mode = items[key]?.mode, mode == "select" || mode == "list" {
                typedDict[key] = strVal
                continue
            }
            let fmt = items[key]?.format
            if fmt == "boolean" {
                typedDict[key] = (strVal.lowercased() == "true")
            } else if fmt == "number" {
                if let iVal = Int(strVal) {
                    typedDict[key] = iVal
                } else if let dVal = Double(strVal) {
                    typedDict[key] = dVal
                } else {
                    typedDict[key] = strVal
                }
            } else {
                typedDict[key] = strVal
            }
        }
        if typedDict[Self.cookieKey] == nil {
            typedDict[Self.cookieKey] = (values[Self.cookieKey]?.lowercased() != "false")
        }

        let data = try JSONSerialization.data(withJSONObject: typedDict, options: [])
        return String(data: data, encoding: .utf8)
    }
}
