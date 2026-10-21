import Foundation

/// Một mục Khám phá của nguồn Legado: `{title, url}` (spec §5.2).
///
/// `url` rỗng ⇒ **tiêu đề nhóm** (không bấm được). `url` có thể là URL tương đối, có `{{page}}`, có khối option
/// `,{…}`, hoặc là JS (`@js:` / `<js>`) sinh URL lúc mở mục — giữ **nguyên văn**, engine dựng request.
public struct LegadoExploreEntry: Sendable, Hashable {
    public let title: String
    public let url: String
    /// `style.layout_flexBasisPercent` (0…1) — tỉ lệ chiều rộng ô; `nil` khi không khai (spec §5.2.2).
    public let widthFraction: Double?
    /// Khoá lạ của phần tử mảng (vd `webView`, `method`, `body`) dạng chuỗi JSON object; `nil` khi không có.
    /// Spec §5.2.1: `[UNKNOWN]`, khuyến nghị engine gộp vào option của URL mục đó.
    public let extraJSON: String?

    public init(title: String, url: String, widthFraction: Double? = nil, extraJSON: String? = nil) {
        self.title = title
        self.url = url
        self.widthFraction = widthFraction
        self.extraJSON = extraJSON
    }

    public var isGroupHeader: Bool {
        url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// URL của mục do JS sinh lúc mở (spec §5.2.2, dòng `@js:`/`<js>`).
    public var isScriptURL: Bool {
        Self.isScript(url)
    }

    // MARK: - Phân tích

    /// `exploreUrl` dạng tĩnh → danh sách mục. `nil` khi là **JS** (`@js:` / `<js>` ở đầu, không phân biệt hoa
    /// thường) — engine chạy JS rồi gọi `entries(fromScriptResult:)`. Rỗng ⇒ `[]`.
    public static func parseStatic(_ exploreUrl: String) -> [LegadoExploreEntry]? {
        let trimmed = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if isScript(trimmed) { return nil }
        return entries(fromScriptResult: trimmed)
    }

    /// Kết quả dạng chuỗi (của `exploreUrl` tĩnh hoặc của JS): chuỗi JSON mảng / object, hoặc văn bản `tên::url`.
    public static func entries(fromScriptResult text: String) -> [LegadoExploreEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("[") {
            return entries(fromJSONArray: LegadoModelJSON.parseArray(trimmed) ?? [])
        }
        if trimmed.hasPrefix("{") {
            guard let object = LegadoModelJSON.parseObject(trimmed) else { return [] }
            return entries(fromJSONArray: [object])
        }
        return entries(fromText: trimmed)
    }

    /// Mảng phần tử `{"title", "url", "style", …}` (dạng 1 của spec §5.2.1, hoặc mảng JS trả về).
    /// Phần tử không phải object bị bỏ; phần tử có `type` khác URL (`select`, `button`) bị **ẩn** (đợt 2).
    public static func entries(fromJSONArray array: [Any]) -> [LegadoExploreEntry] {
        var result: [LegadoExploreEntry] = []
        for element in array {
            guard let object = element as? [String: Any] else { continue }
            if let type = LegadoModelCoercion.string(object["type"])?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !type.isEmpty, type != "url" {
                continue
            }
            let title = (LegadoModelCoercion.string(object["title"]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var url = LegadoModelCoercion.string(object["url"]) ?? ""
            if url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "null" { url = "" }
            guard !title.isEmpty || !url.isEmpty else { continue }
            result.append(LegadoExploreEntry(
                title: title,
                url: url,
                widthFraction: widthFraction(object["style"]),
                extraJSON: extraJSON(object)
            ))
        }
        return result
    }

    /// Dạng văn bản (dạng 2 của spec §5.2.1): mục `tên::url` phân cách bằng xuống dòng hoặc `&&`. Dòng chứa JS
    /// (`<js>`/`@js:`) không tách theo `&&` (JS có thể chứa `&&`). Dòng không có `::` ⇒ tiêu đề nhóm; dòng `null` bị bỏ.
    public static func entries(fromText text: String) -> [LegadoExploreEntry] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var result: [LegadoExploreEntry] = []
        for line in normalized.components(separatedBy: "\n") {
            let lowered = line.lowercased()
            let segments = (lowered.contains("<js>") || lowered.contains("@js:"))
                ? [line]
                : line.components(separatedBy: "&&")
            for segment in segments {
                let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.lowercased() != "null" else { continue }
                guard let separator = trimmed.range(of: "::") else {
                    result.append(LegadoExploreEntry(title: trimmed, url: ""))
                    continue
                }
                let title = String(trimmed[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let url = String(trimmed[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(LegadoExploreEntry(title: title, url: url))
            }
        }
        return result
    }

    /// `@js:` hoặc `<js>` ở đầu chuỗi (sau khi trim), không phân biệt hoa thường (spec §0.6).
    public static func isScript(_ text: String) -> Bool {
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4).lowercased()
        return head == "@js:" || head == "<js>"
    }

    // MARK: - Helpers

    private static let knownKeys: Set<String> = ["title", "url", "style", "type"]

    private static func widthFraction(_ style: Any?) -> Double? {
        let object: [String: Any]?
        if let dictionary = style as? [String: Any] {
            object = dictionary
        } else if let text = style as? String {
            object = LegadoModelJSON.parseObject(text)
        } else {
            object = nil
        }
        guard let raw = object?["layout_flexBasisPercent"] else { return nil }
        if let number = raw as? NSNumber, !LegadoModelCoercion.isBoolean(number) {
            return number.doubleValue
        }
        if let text = raw as? String {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func extraJSON(_ object: [String: Any]) -> String? {
        let extras = object.filter { !knownKeys.contains($0.key) && !($0.value is NSNull) }
        guard !extras.isEmpty else { return nil }
        return LegadoModelJSON.serializedString(extras)
    }
}
