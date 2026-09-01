import Foundation

/// Một đoạn rule đã biên dịch — tương ứng `AnalyzeRule.SourceRule`.
///
/// Một chuỗi rule của Legado có thể tách thành **nhiều** đoạn: phần selector, các khối `@js:` /
/// `<js>`, và phần thay thế `##`. Kết quả đoạn trước là biến `result` của đoạn sau.
public struct LegadoCompiledRule {
    public let mode: LegadoRuleMode
    /// Thân rule đã bỏ tiền tố chế độ, bỏ `@put:{…}` và bỏ đuôi `##…`.
    public let rule: String
    /// `##regex` — regex thay thế áp lên **kết quả** của đoạn này.
    public let replaceRegex: String?
    /// Chuỗi thay thế (phần giữa hai `##`), rỗng nghĩa là xoá.
    public let replacement: String
    /// `###` (ba dấu) ⇒ chỉ thay lần khớp đầu tiên (`AnalyzeRule.kt:530`).
    public let replaceFirstOnly: Bool
    /// `@put:{key: rule}` — chạy rule con rồi nhớ giá trị vào túi biến.
    public let putMap: [String: String]

    public init(
        mode: LegadoRuleMode,
        rule: String,
        replaceRegex: String? = nil,
        replacement: String = "",
        replaceFirstOnly: Bool = false,
        putMap: [String: String] = [:]
    ) {
        self.mode = mode
        self.rule = rule
        self.replaceRegex = replaceRegex
        self.replacement = replacement
        self.replaceFirstOnly = replaceFirstOnly
        self.putMap = putMap
    }

    public var hasReplacement: Bool {
        !(replaceRegex ?? "").isEmpty
    }
}
