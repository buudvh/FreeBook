import Foundation

/// Một phần tử trong AST của pattern rule dịch Quick Translate.
///
/// AST thay cho `NSRegularExpression`: token ràng buộc từ điển (`<ne>/<pn>/<vp>/<w>`) không diễn tả
/// được bằng regex vì phải tra trie tại đúng vị trí capture, và boundary guard của `<n>/<y>` cần so
/// một ký tự liền kề ở input chứ không phải lookaround.
///
/// Mọi độ dài và vị trí trong phần tử này đếm theo **UTF-16** để range trao ra Reader/TTS dùng được
/// ngay mà không phải quy đổi.
public struct QuickTranslationRuleElement: Sendable {
    /// Nhóm từ điển mà một token được phép nuốt. `<w>` mở thành `[.name, .pronoun, .vietPhrase]`
    /// và thử theo thứ tự khai báo; `<hv>` là đúng một ký tự Hán, render bằng bảng `PhienAm`.
    public enum DictionaryKind: String, Sendable {
        case name = "ne"
        case pronoun = "pn"
        case vietPhrase = "vp"
        case hanViet = "hv"
    }

    /// `indirect` vì nhánh `group` chứa lại chính phần tử này.
    public indirect enum Kind: Sendable {
        /// Chuỗi ký tự thường (đã gộp các ký tự liền nhau, đã bỏ dấu `\` escape).
        case literal([UInt16])
        /// `<n>` (`isDigitwise == false`) hoặc `<y>` (`isDigitwise == true`).
        case numeral(isDigitwise: Bool)
        /// `<L>` — đúng một nhãn chương, sinh tên nhãn tiếng Việt.
        case chapterLabel
        /// `<ne>/<pn>/<vp>/<hv>/<w>` — phải khớp một entry của từ điển tương ứng.
        case dictionary([DictionaryKind])
        /// `(a|b)` — mỗi alternative là một dãy phần tử; nhóm **không** sinh capture.
        case group([[QuickTranslationRuleElement]])
    }

    public var kind: Kind
    /// Cú pháp token nguyên gốc của phần tử này. Matcher dùng `kind` đã hạ xuống, còn policy dùng
    /// metadata này để phân biệt `<w>` với tổ hợp các token từ điển tương đương.
    public var sourceTokenKinds: Set<QuickTranslationRuleTokenSettings.Kind>
    /// Số ký tự UTF-16 tối thiểu token được nuốt (`:min-max`). Phần tử literal/group không dùng.
    public var minLength: Int
    public var maxLength: Int
    /// `(a|b)?` hoặc `<x>?` — vắng thì `{i}` render chuỗi rỗng.
    public var isOptional: Bool
    /// Thứ tự capture của token, đánh số theo thứ tự xuất hiện (kể cả token nằm trong group).
    public var captureIndex: Int?
    /// Cờ do compiler đặt: chặn token số nuốt một phần chuỗi số dài hơn ở phía tương ứng.
    /// Chỉ đặt khi phần tử liền kề **không** tiếp tục chuỗi số (xem `QuickTranslationRuleCompiler`).
    public var guardsLeft: Bool
    public var guardsRight: Bool

    public init(
        kind: Kind,
        sourceTokenKinds: Set<QuickTranslationRuleTokenSettings.Kind> = [],
        minLength: Int = 1,
        maxLength: Int = 1,
        isOptional: Bool = false,
        captureIndex: Int? = nil,
        guardsLeft: Bool = false,
        guardsRight: Bool = false
    ) {
        self.kind = kind
        self.sourceTokenKinds = sourceTokenKinds
        self.minLength = minLength
        self.maxLength = maxLength
        self.isOptional = isOptional
        self.captureIndex = captureIndex
        self.guardsLeft = guardsLeft
        self.guardsRight = guardsRight
    }

    /// Token có sinh capture hay không (literal và group thì không).
    public var isToken: Bool {
        switch kind {
        case .literal, .group: return false
        case .numeral, .chapterLabel, .dictionary: return true
        }
    }

    /// Ký tự đầu / cuối của mọi nhánh literal — dùng để quyết định boundary guard.
    /// `nil` khi phần tử không phải literal hoặc group toàn literal.
    public var leadingLiteralUnits: [UInt16]? {
        switch kind {
        case .literal(let units):
            return units.first.map { [$0] }
        case .group(let alternatives):
            var result: [UInt16] = []
            for alternative in alternatives {
                guard let first = alternative.first, let units = first.leadingLiteralUnits else { return nil }
                result.append(contentsOf: units)
            }
            return result.isEmpty ? nil : result
        case .numeral, .chapterLabel, .dictionary:
            return nil
        }
    }

    public var trailingLiteralUnits: [UInt16]? {
        switch kind {
        case .literal(let units):
            return units.last.map { [$0] }
        case .group(let alternatives):
            var result: [UInt16] = []
            for alternative in alternatives {
                guard let last = alternative.last, let units = last.trailingLiteralUnits else { return nil }
                result.append(contentsOf: units)
            }
            return result.isEmpty ? nil : result
        case .numeral, .chapterLabel, .dictionary:
            return nil
        }
    }

    /// Độ dài UTF-16 nhỏ nhất / lớn nhất mà phần tử có thể chiếm.
    public var minimumWidth: Int {
        if isOptional { return 0 }
        switch kind {
        case .literal(let units): return units.count
        case .numeral, .chapterLabel, .dictionary: return minLength
        case .group(let alternatives):
            return alternatives.map { $0.reduce(0) { $0 + $1.minimumWidth } }.min() ?? 0
        }
    }

    public var maximumWidth: Int {
        switch kind {
        case .literal(let units): return units.count
        case .numeral, .chapterLabel, .dictionary: return maxLength
        case .group(let alternatives):
            return alternatives.map { $0.reduce(0) { $0 + $1.maximumWidth } }.max() ?? 0
        }
    }
}
