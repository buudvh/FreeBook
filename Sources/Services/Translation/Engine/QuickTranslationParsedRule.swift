import Foundation

/// Một rule đã tách khỏi văn bản nguồn và đã dựng AST, **chưa** validate và chưa tính chỉ số ưu tiên.
public struct QuickTranslationParsedRule: Sendable {
    /// Số dòng vật lý 1-based trong file nguồn — cũng là tiebreak cuối của thứ tự ưu tiên.
    public let sourceLine: Int
    public let rawLine: String
    /// LHS nguyên văn, dùng cho màn hình quản lý và cho cảnh báo `DUPLICATE_PATTERN`.
    public let pattern: String
    /// RHS nguyên văn (còn `{i}`).
    public let replacement: String
    public let elements: [QuickTranslationRuleElement]
    /// Số token sinh capture, đánh số theo thứ tự xuất hiện.
    public let captureCount: Int

    public init(
        sourceLine: Int,
        rawLine: String,
        pattern: String,
        replacement: String,
        elements: [QuickTranslationRuleElement],
        captureCount: Int
    ) {
        self.sourceLine = sourceLine
        self.rawLine = rawLine
        self.pattern = pattern
        self.replacement = replacement
        self.elements = elements
        self.captureCount = captureCount
    }
}
