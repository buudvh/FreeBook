import Foundation

/// Một rule đã validate và tính xong mọi thứ matcher cần ở runtime.
///
/// Ba chỉ số ưu tiên (`literalLength`, `wildcardCapacity`, `sourceLine`) giữ **đúng** ngữ nghĩa của
/// `executeRules` trong reference, chỉ đổi cách sinh candidate.
public struct QuickTranslationCompiledRule: Sendable {
    /// Một mảnh của RHS: chữ cố định, hoặc tham chiếu `{i}` tới capture thứ `i`.
    public enum TemplateSegment: Sendable {
        case text(String)
        case capture(Int)
    }

    public let sourceLine: Int
    public let pattern: String
    public let replacement: String
    public let elements: [QuickTranslationRuleElement]
    public let template: [TemplateSegment]
    public let captureCount: Int

    /// Tổng số ký tự literal ngoài token. Group không optional đóng góp alternative dài nhất,
    /// group optional đóng góp 0 (giống `compile()` của reference).
    public let literalLength: Int
    /// Tổng `max` của mọi token. Token từ điển không khai range dùng mặc định 12 như reference —
    /// dữ liệu trie hiện có không expose độ dài entry dài nhất.
    public let wildcardCapacity: Int

    /// Chuỗi literal liên tục **dài nhất** ngoài mọi token và mọi group — điều kiện *cần* của mọi
    /// match, nên dùng làm khoá prefilter. Rỗng ⇒ rule vào danh sách "always try".
    public let requiredLiteral: [UInt16]
    /// Bề rộng nhỏ nhất / lớn nhất của phần pattern **đứng trước** `requiredLiteral`, để suy ra
    /// vị trí bắt đầu có thể của rule từ vị trí literal tìm được trong input.
    public let requiredLiteralPrefixMin: Int
    public let requiredLiteralPrefixMax: Int

    /// Các nhóm từ điển rule này cần. Dùng cho `DICT_TOKEN_WITHOUT_DICTIONARY` ở màn hình quản lý;
    /// runtime không chặn theo cờ này — thiếu từ điển thì token đơn giản không có ứng viên nào.
    public let requiredDictionaryKinds: [QuickTranslationRuleElement.DictionaryKind]

    public init(
        sourceLine: Int,
        pattern: String,
        replacement: String,
        elements: [QuickTranslationRuleElement],
        template: [TemplateSegment],
        captureCount: Int,
        literalLength: Int,
        wildcardCapacity: Int,
        requiredLiteral: [UInt16],
        requiredLiteralPrefixMin: Int,
        requiredLiteralPrefixMax: Int,
        requiredDictionaryKinds: [QuickTranslationRuleElement.DictionaryKind]
    ) {
        self.sourceLine = sourceLine
        self.pattern = pattern
        self.replacement = replacement
        self.elements = elements
        self.template = template
        self.captureCount = captureCount
        self.literalLength = literalLength
        self.wildcardCapacity = wildcardCapacity
        self.requiredLiteral = requiredLiteral
        self.requiredLiteralPrefixMin = requiredLiteralPrefixMin
        self.requiredLiteralPrefixMax = requiredLiteralPrefixMax
        self.requiredDictionaryKinds = requiredDictionaryKinds
    }

    /// Render RHS từ các capture đã khớp. Capture vắng (token optional) render chuỗi rỗng.
    public func render(captures: [String]) -> String {
        var output = ""
        for segment in template {
            switch segment {
            case .text(let text):
                output += text
            case .capture(let index):
                if index < captures.count {
                    output += captures[index]
                }
            }
        }
        return output
    }
}
