import Foundation

/// Matcher AST-walk có backtracking, **không** dùng `NSRegularExpression`.
///
/// Lý do không mượn đường regex của reference: bốn yêu cầu của bộ rule không diễn tả được bằng regex
/// hoặc chỉ diễn tả được rất vụng — token ràng buộc từ điển (phải tra trie tại vị trí capture),
/// boundary guard có điều kiện cho `<n>/<y>`, `<L>`/`<hv>` đúng một ký tự, và group lồng + `\` escape
/// + `<x>?`. Đổi lại còn tránh dựng hàng nghìn object regex và bridge Swift↔ICU cho mỗi lần scan.
///
/// Mọi vị trí và độ dài đếm theo **UTF-16** để range trao ra ngoài dùng được ngay.
public final class QuickTranslationRuleMatcher {
    /// Một capture đã khớp: chuỗi **đã render** cộng range **nguồn** đã bị token nuốt.
    ///
    /// Vì sao gộp text và range vào **một** struct thay vì hai mảng song song: backtracking rollback
    /// bằng mẫu `let saved = captures` … `captures = saved` ở **5** chỗ trong file này; hai mảng chỉ
    /// cần quên một chỗ là range lệch âm thầm mà không có gì báo lỗi.
    public struct Capture: Sendable {
        public let text: String
        /// `nil` khi token optional vắng mặt — không có ký tự nguồn nào bị nuốt.
        public let sourceRange: NSRange?

        public init(text: String, sourceRange: NSRange?) {
            self.text = text
            self.sourceRange = sourceRange
        }
    }

    public struct Match {
        public let start: Int
        public let length: Int
        public let captures: [Capture]

        /// Dạng `[String]` cho `QuickTranslationCompiledRule.render(captures:)` — hàm đó giữ nguyên
        /// chữ ký cũ vì nó chỉ cần chữ, không cần range.
        public var captureTexts: [String] { captures.map(\.text) }
    }

    private struct Frame {
        let elements: [QuickTranslationRuleElement]
        let index: Int
    }

    /// Chặn nổ backtracking. Pattern thật rất ngắn (≤ 8 phần tử, `max ≤ 12`) nên cap không bao giờ
    /// chạm với dữ liệu hiện có; nó chỉ để một rule bệnh lý không treo Reader.
    private static let stepCap = 4_000

    private let units: [UInt16]
    private let text: NSString
    private let dictionaries: QuickTranslationDictionaryToken

    private var captures: [Capture] = []
    private var steps = 0
    /// Rule vừa thử có chạm cap hay không — engine dùng để ghi cảnh báo `RULE_TOO_COMPLEX`.
    public private(set) var didExceedStepCap = false

    public init(text: String, dictionaries: QuickTranslationDictionaryToken) {
        self.units = Array(text.utf16)
        self.text = text as NSString
        self.dictionaries = dictionaries
    }

    public var length: Int { units.count }

    /// Thử khớp `rule` **đúng tại** `start`. Trả về match đầu tiên tìm được (greedy: token thử độ dài
    /// dài → ngắn, group thử alternative theo thứ tự khai báo rồi mới thử nhánh vắng).
    public func match(_ rule: QuickTranslationCompiledRule, at start: Int) -> Match? {
        guard start >= 0, start <= units.count else { return nil }
        captures = Array(
            repeating: Capture(text: "", sourceRange: nil),
            count: rule.captureCount
        )
        steps = 0
        didExceedStepCap = false

        guard let end = walk([Frame(elements: rule.elements, index: 0)], start) else { return nil }
        return Match(start: start, length: end - start, captures: captures)
    }

    // MARK: - AST walk

    private func walk(_ stack: [Frame], _ position: Int) -> Int? {
        steps += 1
        if steps > Self.stepCap {
            didExceedStepCap = true
            return nil
        }

        var stack = stack
        while let last = stack.last, last.index >= last.elements.count {
            stack.removeLast()
        }
        guard let frame = stack.last else { return position }

        let element = frame.elements[frame.index]
        var advanced = stack
        advanced[advanced.count - 1] = Frame(elements: frame.elements, index: frame.index + 1)

        switch element.kind {
        case .literal(let literal):
            guard position + literal.count <= units.count else { return nil }
            for offset in literal.indices where units[position + offset] != literal[offset] {
                return nil
            }
            return walk(advanced, position + literal.count)

        case .group(let alternatives):
            let saved = captures
            for alternative in alternatives {
                var pushed = advanced
                pushed.append(Frame(elements: alternative, index: 0))
                if let end = walk(pushed, position) { return end }
                captures = saved
            }
            guard element.isOptional else { return nil }
            return walk(advanced, position)

        case .numeral(let numeralKind):
            return walkNumeral(element, kind: numeralKind, advanced, position)

        case .chapterLabel:
            let saved = captures
            if position < units.count,
               QuickTranslationNumberFormatter.chapterLabelUnits.contains(units[position]) {
                let value = text.substring(with: NSRange(location: position, length: 1))
                store(
                    QuickTranslationNumberFormatter.renderChapterLabel(value),
                    sourceRange: NSRange(location: position, length: 1),
                    for: element
                )
                if let end = walk(advanced, position + 1) { return end }
                captures = saved
            }
            return skipOptional(element, advanced, position)

        case .dictionary(let kinds):
            return walkDictionary(element, kinds: kinds, advanced, position)
        }
    }

    private func walkNumeral(
        _ element: QuickTranslationRuleElement,
        kind: QuickTranslationRuleElement.NumeralKind,
        _ advanced: [Frame],
        _ position: Int
    ) -> Int? {
        let allowed = QuickTranslationNumberFormatter.units(for: kind)

        // Guard bên trái: ký tự ngay trước match thuộc cùng lớp số ⇒ token đang nuốt phần giữa của
        // một chuỗi số dài hơn.
        if element.guardsLeft, position > 0, allowed.contains(units[position - 1]) {
            return skipOptional(element, advanced, position)
        }

        var run = 0
        while position + run < units.count, allowed.contains(units[position + run]) {
            run += 1
        }

        // Guard bên phải: nếu buộc phải nuốt hết chuỗi số thì chỉ có duy nhất độ dài `run` hợp lệ —
        // mọi độ dài ngắn hơn đều để lại ký tự cùng lớp ở ngay sau match.
        let upper = element.guardsRight ? run : min(run, element.maxLength)
        let lower = element.guardsRight ? run : element.minLength
        guard upper <= element.maxLength, upper >= element.minLength, lower <= upper else {
            return skipOptional(element, advanced, position)
        }

        let saved = captures
        var candidate = upper
        while candidate >= lower {
            let value = text.substring(with: NSRange(location: position, length: candidate))
            let rendered: String
            switch kind {
            case .chinese:
                rendered = QuickTranslationNumberFormatter.renderNumeral(value)
            case .digitwise:
                rendered = QuickTranslationNumberFormatter.renderDigitwise(value)
            case .hanDigits:
                rendered = QuickTranslationNumberFormatter.renderHanDigits(value)
            case .asciiDigits:
                rendered = QuickTranslationNumberFormatter.renderAsciiDigits(value)
            case .magnitude:
                rendered = QuickTranslationNumberFormatter.renderMagnitude(value)
            case .latinLetters:
                rendered = QuickTranslationNumberFormatter.renderLatinLetters(value)
            }
            store(
                rendered,
                sourceRange: NSRange(location: position, length: candidate),
                for: element
            )
            if let end = walk(advanced, position + candidate) { return end }
            captures = saved
            candidate -= 1
        }

        return skipOptional(element, advanced, position)
    }

    private func walkDictionary(
        _ element: QuickTranslationRuleElement,
        kinds: [QuickTranslationRuleElement.DictionaryKind],
        _ advanced: [Frame],
        _ position: Int
    ) -> Int? {
        let available = min(element.maxLength, units.count - position)
        guard available >= element.minLength else {
            return skipOptional(element, advanced, position)
        }

        let window = text.substring(with: NSRange(location: position, length: available))
        let candidates = dictionaries.candidates(
            kinds: kinds,
            in: window,
            minLength: element.minLength,
            maxLength: element.maxLength
        )

        let saved = captures
        for candidate in candidates {
            store(
                candidate.meaning,
                sourceRange: NSRange(location: position, length: candidate.length),
                for: element
            )
            if let end = walk(advanced, position + candidate.length) { return end }
            captures = saved
        }

        return skipOptional(element, advanced, position)
    }

    /// Token optional vắng mặt ⇒ capture rỗng, `{i}` render chuỗi rỗng; `sourceRange` là `nil` vì
    /// không có ký tự nguồn nào bị nuốt.
    private func skipOptional(
        _ element: QuickTranslationRuleElement,
        _ advanced: [Frame],
        _ position: Int
    ) -> Int? {
        guard element.isOptional else { return nil }
        store("", sourceRange: nil, for: element)
        return walk(advanced, position)
    }

    private func store(_ value: String, sourceRange: NSRange?, for element: QuickTranslationRuleElement) {
        guard let index = element.captureIndex, index < captures.count else { return }
        captures[index] = Capture(text: value, sourceRange: sourceRange)
    }
}
