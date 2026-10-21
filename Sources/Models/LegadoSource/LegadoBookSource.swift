import Foundation

/// Một nguồn truyện JSON kiểu Legado — bản chụp **đã parse** từ object JSON gốc (spec §1).
///
/// - `rawJSON` là bytes của **toàn bộ** object gốc (kể cả khoá lạ) — đúng nội dung `source.json` trên đĩa. Engine cần
///   khoá bất kỳ thì đọc `fields` (khoá cấp nguồn, đã đổi sang chuỗi) hoặc `rawObject()`.
/// - Decode khoan dung theo spec §1.2: số-hoặc-chuỗi, bool-hoặc-số-hoặc-chuỗi, nhóm rule là object hoặc chuỗi JSON
///   lồng, `null` = vắng. Mặc định khi vắng: `bookSourceType = 0`, `enabled = true`, `enabledExplore = true`,
///   `enabledCookieJar = false`, số = 0, rule = `""`.
/// - `bookSourceUrl` giữ **nguyên văn** (kể cả `#…` và khoảng trắng — spec §1.4); so trùng/định danh dùng
///   `trimmedSourceUrl`.
public struct LegadoBookSource: Sendable {
    /// Lỗi đọc `source.json` / object nguồn.
    public enum DecodeError: LocalizedError, Sendable {
        case notAnObject

        public var errorDescription: String? {
            switch self {
            case .notAnObject: return "Dữ liệu nguồn Legado không phải object JSON"
            }
        }
    }

    /// Khoá của 5 nhóm rule (và `ruleReview`) — không chép vào `fields`.
    public static let ruleGroupKeys: Set<String> = [
        "ruleSearch", "ruleExplore", "ruleBookInfo", "ruleToc", "ruleContent", "ruleReview"
    ]

    /// Mọi khoá cấp nguồn (trừ nhóm rule) → chuỗi theo spec §1.2. Object/mảng → chuỗi JSON. `null` bị bỏ.
    public let fields: [String: String]
    /// Bytes JSON của object gốc. `internal(set)`: importer gắn bytes đã chuẩn hoá sau khi phân loại.
    public internal(set) var rawJSON: Data

    public let bookSourceUrl: String
    public let bookSourceName: String
    public let bookSourceGroup: String
    public let bookSourceComment: String
    /// Sau ép kiểu; vắng / không parse được ⇒ 0 (spec §1.2, §1.6).
    public let bookSourceType: Int
    public let kind: LegadoSourceKind
    public let enabled: Bool
    public let enabledExplore: Bool
    public let enabledCookieJar: Bool
    public let customOrder: Int
    public let weight: Int
    public let lastUpdateTime: Int64
    public let respondTime: Int64

    public let ruleSearch: LegadoSearchRule
    public let ruleExplore: LegadoSearchRule
    public let ruleBookInfo: LegadoBookInfoRule
    public let ruleToc: LegadoTocRule
    public let ruleContent: LegadoContentRule

    /// Dựng từ object đã parse; `rawJSON` = bytes JSON ổn định của chính object đó.
    public init(jsonObject object: [String: Any]) {
        self.init(jsonObject: object, rawJSON: LegadoModelJSON.serialize(object) ?? Data())
    }

    /// Đọc từ bytes của **một** object (nội dung `source.json`). Giữ nguyên `data` làm `rawJSON`.
    public init(data: Data) throws {
        guard let object = LegadoModelJSON.parseDocument(data: data) as? [String: Any] else {
            throw DecodeError.notAnObject
        }
        self.init(jsonObject: object, rawJSON: data)
    }

    init(jsonObject object: [String: Any], rawJSON: Data) {
        self.rawJSON = rawJSON
        var fields: [String: String] = [:]
        for (key, value) in object where !Self.ruleGroupKeys.contains(key) {
            if let text = LegadoModelCoercion.string(value) { fields[key] = text }
        }
        self.fields = fields

        bookSourceUrl = fields["bookSourceUrl"] ?? ""
        bookSourceName = fields["bookSourceName"] ?? ""
        bookSourceGroup = fields["bookSourceGroup"] ?? ""
        bookSourceComment = fields["bookSourceComment"] ?? ""
        let type = LegadoModelCoercion.int(object["bookSourceType"]) ?? 0
        bookSourceType = type
        kind = LegadoSourceKind(bookSourceType: type)
        enabled = LegadoModelCoercion.bool(object["enabled"]) ?? true
        enabledExplore = LegadoModelCoercion.bool(object["enabledExplore"]) ?? true
        enabledCookieJar = LegadoModelCoercion.bool(object["enabledCookieJar"]) ?? false
        customOrder = LegadoModelCoercion.int(object["customOrder"]) ?? 0
        weight = LegadoModelCoercion.int(object["weight"]) ?? 0
        lastUpdateTime = LegadoModelCoercion.int64(object["lastUpdateTime"]) ?? 0
        respondTime = LegadoModelCoercion.int64(object["respondTime"]) ?? 0

        ruleSearch = LegadoSearchRule(values: LegadoModelCoercion.stringMap(object["ruleSearch"]))
        ruleExplore = LegadoSearchRule(values: LegadoModelCoercion.stringMap(object["ruleExplore"]))
        ruleBookInfo = LegadoBookInfoRule(values: LegadoModelCoercion.stringMap(object["ruleBookInfo"]))
        ruleToc = LegadoTocRule(values: LegadoModelCoercion.stringMap(object["ruleToc"]))
        ruleContent = LegadoContentRule(values: LegadoModelCoercion.stringMap(object["ruleContent"]))
    }

    // MARK: - Truy cập khoá cấp nguồn

    /// Khoá cấp nguồn dạng chuỗi; vắng ⇒ `""`.
    public func field(_ key: String) -> String {
        fields[key] ?? ""
    }

    /// Object gốc parse lại từ `rawJSON` (đắt — chỉ dùng khi cần khoá lồng không có accessor).
    public func rawObject() -> [String: Any]? {
        LegadoModelJSON.parseDocument(data: rawJSON) as? [String: Any]
    }

    /// Nội dung `rawJSON` dạng chuỗi (đưa vào JS nguyên văn).
    public var rawJSONString: String {
        String(decoding: rawJSON, as: UTF8.self)
    }

    public var concurrentRate: String { field("concurrentRate") }
    public var header: String { field("header") }
    public var searchUrl: String { field("searchUrl") }
    public var exploreUrl: String { field("exploreUrl") }
    public var bookUrlPattern: String { field("bookUrlPattern") }
    public var jsLib: String { field("jsLib") }
    public var loginUrl: String { field("loginUrl") }
    public var loginUi: String { field("loginUi") }
    public var loginCheckJs: String { field("loginCheckJs") }
    public var variableComment: String { field("variableComment") }
    public var coverDecodeJs: String { field("coverDecodeJs") }
}
