import Foundation

/// Một lỗi hoặc cảnh báo gắn với **một dòng** trong file rule dịch.
///
/// Phân loại theo tiêu chí: `hard` = engine có thể hiểu sai ý người viết ⇒ chặn không nạp cả file;
/// `disabling` = cú pháp đúng nhưng thiếu điều kiện runtime (từ điển chưa nạp) ⇒ chỉ vô hiệu rule đó;
/// `warning` = rule chỉ vô hiệu hoặc đáng ngờ, không làm sai rule khác.
public struct QuickTranslationRuleIssue: Identifiable, Hashable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        case hard = 0
        case disabling = 1
        case warning = 2

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public enum Code: String, Sendable {
        case unparseableRuleLine = "UNPARSEABLE_RULE_LINE"
        case emptyPattern = "EMPTY_PATTERN"
        case unknownTokenName = "UNKNOWN_TOKEN_NAME"
        case unbalancedParens = "UNBALANCED_PARENS"
        case invalidRefIndex = "INVALID_REF_INDEX"
        case unusedCapture = "UNUSED_CAPTURE"
        case noLiteralAnchor = "NO_LITERAL_ANCHOR"
        case dictTokenWithoutDictionary = "DICT_TOKEN_WITHOUT_DICTIONARY"
        case literalSpaceInPattern = "LITERAL_SPACE_IN_PATTERN"
        case multipleConsecutiveWildcards = "MULTIPLE_CONSECUTIVE_WILDCARDS"
        case duplicatePattern = "DUPLICATE_PATTERN"
        case weakAnchor = "WEAK_ANCHOR"
        case ruleTooComplex = "RULE_TOO_COMPLEX"

        public var severity: Severity {
            switch self {
            case .unparseableRuleLine, .emptyPattern, .unknownTokenName,
                 .unbalancedParens, .invalidRefIndex, .unusedCapture, .noLiteralAnchor:
                return .hard
            case .dictTokenWithoutDictionary:
                return .disabling
            case .literalSpaceInPattern, .multipleConsecutiveWildcards,
                 .duplicatePattern, .weakAnchor, .ruleTooComplex:
                return .warning
            }
        }
    }

    public let id = UUID()
    /// Số dòng vật lý **1-based** trong file nguồn, giữ nguyên để người dùng sửa ngoài app.
    public let sourceLine: Int
    public let code: Code
    public let message: String
    /// Nguyên văn dòng, cắt bớt nếu quá dài để không phình bộ nhớ khi file có 17k dòng.
    public let rawLine: String

    public var severity: Severity { code.severity }

    public init(sourceLine: Int, code: Code, message: String, rawLine: String) {
        self.sourceLine = sourceLine
        self.code = code
        self.message = message
        self.rawLine = rawLine.count > 160 ? String(rawLine.prefix(160)) + "…" : rawLine
    }

    public static func == (lhs: QuickTranslationRuleIssue, rhs: QuickTranslationRuleIssue) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
