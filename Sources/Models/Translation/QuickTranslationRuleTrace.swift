import Foundation

/// Một lần khớp rule trên **một đoạn văn**, dựng bởi `QuickTranslationRuleDiagnostics` cho màn
/// "Check rule" của Reader.
///
/// Khác `QuickTranslationRewriteResult` ở chỗ: bản đồ đoạn của kết quả rewrite chỉ giữ rule **thắng**,
/// còn ở đây giữ **cả** rule thua chồng lấn, rule đang tắt và rule bị token tắt — vì mục đích của màn
/// đó là cho người dùng thấy tranh chấp rồi bật/tắt ngay.
public struct QuickTranslationRuleTrace: Identifiable, Sendable {
    /// Một token đã khớp trong cụm, kèm nghĩa đã render — dải "nghĩa của token" hiển thị đúng cái này.
    public struct Capture: Sendable {
        public let index: Int
        public let sourceText: String
        public let renderedText: String
        /// `nil` khi token optional vắng mặt.
        public let sourceRange: NSRange?

        public init(index: Int, sourceText: String, renderedText: String, sourceRange: NSRange?) {
            self.index = index
            self.sourceText = sourceText
            self.renderedText = renderedText
            self.sourceRange = sourceRange
        }
    }

    public enum Status: Sendable, Equatable {
        /// Rule **thắng**: đang thực sự đổi text ở vị trí này.
        case applied
        /// Khớp nhưng chồng lấn và thua theo thứ tự ưu tiên; `toSourceLine` là rule đã thắng.
        case lostOverlap(toSourceLine: Int)
        /// Mẫu nằm trong file tắt **chung** ⇒ tắt cho mọi truyện.
        case disabledGlobally
        /// Mẫu nằm trong file tắt **riêng** của truyện đang đọc.
        case disabledForBook
        /// Một cú pháp token của rule đang bị tắt ở Cấu hình token rule.
        case tokenDisabled
        /// Rule chạm cap backtracking của matcher tại vị trí này.
        case tooComplex

        public var isDisabled: Bool {
            switch self {
            case .disabledGlobally, .disabledForBook, .tokenDisabled: return true
            case .applied, .lostOverlap, .tooComplex: return false
            }
        }
    }

    /// Handle của hàng trong snapshot — thứ `deleteRule(rowID:)` cần. **Không** dùng `sourceLine`
    /// làm định danh: số dòng đổi sau mỗi lần thêm/xoá (nguyên nhân crash đã sửa ở 1.3.271).
    public let rowID: UUID
    public let scope: QuickTranslationRuleScope
    public let pattern: String
    public let replacement: String
    public let sourceLine: Int
    /// Range UTF-16 của cụm nguồn đã khớp, tính trên **đoạn văn gốc** truyền vào `diagnose`.
    public let sourceRange: NSRange
    public let matchedText: String
    public let rendered: String
    public let captures: [Capture]
    public let status: Status
    /// Cụm này có giao với vùng người dùng đang bôi đen hay không — dùng để đẩy lên đầu dải chip.
    public let isTouchingSelection: Bool

    /// Định danh **xác định** (không phải UUID mới mỗi lượt) để `ForEach` không dựng lại dải chip sau
    /// mỗi lần chẩn đoán lại. Một rule khớp nhiều vị trí trong đoạn ⇒ mỗi vị trí một chip riêng.
    public var id: String { "\(rowID.uuidString)#\(sourceRange.location)" }

    public init(
        rowID: UUID,
        scope: QuickTranslationRuleScope,
        pattern: String,
        replacement: String,
        sourceLine: Int,
        sourceRange: NSRange,
        matchedText: String,
        rendered: String,
        captures: [Capture],
        status: Status,
        isTouchingSelection: Bool
    ) {
        self.rowID = rowID
        self.scope = scope
        self.pattern = pattern
        self.replacement = replacement
        self.sourceLine = sourceLine
        self.sourceRange = sourceRange
        self.matchedText = matchedText
        self.rendered = rendered
        self.captures = captures
        self.status = status
        self.isTouchingSelection = isTouchingSelection
    }
}
