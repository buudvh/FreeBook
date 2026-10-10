import Foundation

/// Một model mà tài khoản đang đăng nhập được phép dùng, khám phá qua RPC `GetUserStatus` (`otAQ7b`).
///
/// Header model dựng **lúc gọi** từ `id`/`capacity`/`modelNumber` nên app không găm cứng id hex nào —
/// Google đổi tên/đổi tier là app vẫn theo kịp mà không cần phát hành bản mới. Cấu trúc header và
/// cách suy capacity chép theo `AvailableModel` của `gemini-webapi`.
public struct GeminiWebModel: Sendable, Equatable, Codable {
    /// Id hex nội bộ của Google (vd. `fbb127bbb056c959`).
    public let id: String
    /// Tên dùng trong `availableModels`/`selectedModel` của profile, dạng `gemini-flash`.
    public let name: String
    public let displayName: String
    public let capacity: Int
    /// 12 hay 13 — quyết định vị trí của `capacity` trong header.
    public let capacityField: Int
    public let modelNumber: Int
    public let aliases: [String]

    public static let headerKey = "x-goog-ext-525001261-jspb"

    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        return name == needle || id.lowercased() == needle || aliases.contains(needle)
    }

    /// Giá trị header `x-goog-ext-525001261-jspb`, đã gắn đuôi `…, 1, "<sessionUUID>"` như thư viện tham chiếu.
    public func headerValue(sessionUUID: String) -> String {
        let tail = capacityField == 13 ? "null,\(capacity)" : "\(capacity)"
        return "[1,null,null,null,\"\(id)\",null,null,0,[4,5,6,8],null,null,\(tail),null,null,\(modelNumber),1,\"\(sessionUUID)\"]"
    }

    /// Header của `batchexecute` (không chọn model), cũng gắn đuôi sessionUUID.
    public static func batchHeaderValue(sessionUUID: String) -> String {
        "[1,null,null,null,null,null,null,null,[4,5,6,8],null,null,null,null,null,null,null,\"\(sessionUUID)\"]"
    }

    // MARK: - Dựng từ RPC

    /// Dựng từ một phần tử của `body[15]` trong `GetUserStatus`. Trả `nil` khi thiếu id.
    static func fromRPC(_ data: [Any], capacity: Int, capacityField: Int) -> GeminiWebModel? {
        let id = stringValue(element(data, 0))
        guard !id.isEmpty else { return nil }
        let category = firstNonEmpty(stringValue(element(data, 1)), stringValue(element(data, 10)))
        let display = firstNonEmpty(stringValue(element(data, 11)), stringValue(element(data, 19)), stringValue(element(data, 1)))
        let modelNumber = intValue(element(data, 17)) ?? intValue(element(data, 9)) ?? 1
        let derived = deriveName(id: id, category: category, display: display)
        return GeminiWebModel(
            id: id,
            name: derived.name,
            displayName: firstNonEmpty(display, category, id),
            capacity: capacity,
            capacityField: capacityField,
            modelNumber: modelNumber,
            aliases: derived.aliases
        )
    }

    /// Tier/capability của tài khoản (`body[16]`, `body[17]`) → `(capacity, field)` cho header model.
    static func computeCapacity(tierFlags: [Int], capabilityFlags: [Int]) -> (capacity: Int, field: Int) {
        if tierFlags.contains(21) { return (1, 13) }
        if tierFlags.contains(22) { return (2, 13) }
        if capabilityFlags.contains(115) { return (4, 12) }
        if tierFlags.contains(16) || capabilityFlags.contains(106) { return (3, 12) }
        if tierFlags.contains(8) || capabilityFlags.contains(19) { return (2, 12) }
        return (1, 12)
    }

    /// `gemini-<nhóm>` làm tên chính; bí danh gồm tên nhóm, tên hiển thị (có/không số phiên bản) và id.
    static func deriveName(id: String, category: String, display: String) -> (name: String, aliases: [String]) {
        var aliases = Set<String>()
        if !id.isEmpty { aliases.insert(id.lowercased()) }
        let categoryClean = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayClean = display.trimmingCharacters(in: .whitespacesAndNewlines)
        let majorVersion = displayClean.range(of: #"\d+"#, options: .regularExpression).map { String(displayClean[$0]) }

        var primary = "gemini-\(id)"
        if !categoryClean.isEmpty {
            let slug = slugify(categoryClean)
            aliases.formUnion([categoryClean.lowercased(), slug, "gemini-\(slug)"])
            if let majorVersion { aliases.insert("gemini-\(majorVersion)-\(slug)") }
            primary = "gemini-\(slug)"
        }
        if !displayClean.isEmpty {
            let slug = slugify(displayClean)
            aliases.formUnion([displayClean.lowercased(), slug, "gemini-\(slug)"])
            if categoryClean.isEmpty { primary = "gemini-\(slug)" }
        }
        aliases.insert(primary)
        return (primary, aliases.sorted())
    }

    // MARK: - Phụ trợ

    private static func slugify(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private static func element(_ array: [Any], _ index: Int) -> Any? {
        guard index >= 0, index < array.count else { return nil }
        let value = array[index]
        return value is NSNull ? nil : value
    }

    private static func stringValue(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    private static func firstNonEmpty(_ candidates: String...) -> String {
        candidates.first { !$0.isEmpty } ?? ""
    }
}
