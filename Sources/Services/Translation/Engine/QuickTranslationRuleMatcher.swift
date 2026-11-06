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
    /// bằng mẫu `let saved = captures` … `captures = saved` ở mọi chỗ thử lùi (kể cả `<[>` ở
    /// `QuickTranslationRuleMatcher+Bracket.swift`); hai mảng chỉ cần quên một chỗ là range lệch âm thầm.
    public struct Capture: Sendable {
        public let text: String
        /// `nil` khi token optional vắng mặt — không có ký tự nguồn nào bị nuốt.
        public let sourceRange: NSRange?
        /// `true` chỉ với capture của `<any>` (1.3.686): nó trả **nguyên văn** rồi chuỗi đó còn được tách từ
        /// và dịch lại (Name riêng vẫn áp), nên được phép **bao trọn** Name riêng chứ không chỉ trùng khít
        /// (`QuickTranslationRuleEngine.ruleMatchConflictsWithBookNames`).
        public let allowsEnclosedNames: Bool

        public init(text: String, sourceRange: NSRange?, allowsEnclosedNames: Bool = false) {
            self.text = text
            self.sourceRange = sourceRange
            self.allowsEnclosedNames = allowsEnclosedNames
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

    /// `internal` (không `private`) cho `QuickTranslationRuleMatcher+Bracket.swift`.
    struct Frame {
        let elements: [QuickTranslationRuleElement]
        let index: Int
    }

    /// Chặn nổ backtracking. Pattern thật rất ngắn (≤ 8 phần tử, `max ≤ 12`; `<any>` mặc định 50 nhưng chỉ
    /// thử độ dài để lại đúng chữ cố định theo sau — xem `walkAnyRun`) nên cap không bao giờ
    /// chạm với dữ liệu hiện có; nó chỉ để một rule bệnh lý không treo Reader.
    private static let stepCap = 4_000

    let units: [UInt16]
    let text: NSString
    private let dictionaries: QuickTranslationDictionaryToken
    private let bookNameOccupiedIndices: Set<Int>
    /// Bộ ngoặc của `<[>`/`<]>` cho lượt dịch này (1.3.692) — bản chụp bất biến, không đọc store theo vị trí.
    let brackets: QuickTranslationRuleBracketSet

    /// `rule.slotCount` ô: các ô `{i}` rồi tới ô **ẩn** của từng `<[>` (ký tự mở đã bắt).
    var captures: [Capture] = []
    private var steps = 0
    /// Rule vừa thử có chạm cap hay không — engine dùng để ghi cảnh báo `RULE_TOO_COMPLEX`.
    public private(set) var didExceedStepCap = false

    public init(
        text: String,
        dictionaries: QuickTranslationDictionaryToken,
        bookNameOccupiedIndices: Set<Int> = [],
        brackets: QuickTranslationRuleBracketSet = .defaults
    ) {
        self.units = Array(text.utf16)
        self.text = text as NSString
        self.dictionaries = dictionaries
        self.bookNameOccupiedIndices = bookNameOccupiedIndices
        self.brackets = brackets
    }

    public var length: Int { units.count }

    /// Thử khớp `rule` **đúng tại** `start`. Trả về match đầu tiên tìm được (greedy: token thử độ dài
    /// dài → ngắn, group thử alternative theo thứ tự khai báo rồi mới thử nhánh vắng).
    public func match(_ rule: QuickTranslationCompiledRule, at start: Int) -> Match? {
        guard start >= 0, start <= units.count else { return nil }
        captures = Array(
            repeating: Capture(text: "", sourceRange: nil),
            count: max(rule.captureCount, rule.slotCount)
        )
        steps = 0
        didExceedStepCap = false

        guard let end = walk([Frame(elements: rule.elements, index: 0)], start) else { return nil }
        // Chỉ trả các ô `{i}`: ô ẩn của ngoặc không được ra bản dịch, chẩn đoán hay kiểm Name riêng.
        let visible = captures.count > rule.captureCount ? Array(captures.prefix(rule.captureCount)) : captures
        return Match(start: start, length: end - start, captures: visible)
    }

    // MARK: - AST walk

    func walk(_ stack: [Frame], _ position: Int) -> Int? {
        if Task.isCancelled { return nil }
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

        case .anyRun:
            return walkAnyRun(element, advanced, position)

        // Neo dòng rộng 0: chỉ kiểm điều kiện rồi đi tiếp **tại chỗ**, không capture.
        case .lineStart:
            guard QuickTranslationRuleLineAnchor.isAtLineStart(units, position) else { return nil }
            return walk(advanced, position)

        case .lineEnd:
            guard QuickTranslationRuleLineAnchor.isAtLineEnd(units, position) else { return nil }
            return walk(advanced, position)

        case .openBracket:
            return walkOpenBracket(element, advanced, position)

        case .closeBracket:
            return walkCloseBracket(element, advanced, position)
        }
    }

    private func walkNumeral(
        _ element: QuickTranslationRuleElement,
        kind: QuickTranslationRuleElement.NumeralKind,
        _ advanced: [Frame],
        _ position: Int
    ) -> Int? {
        guard position < units.count else {
            return skipOptional(element, advanced, position)
        }
        let baseAllowed = QuickTranslationNumberFormatter.units(for: kind)
        guard baseAllowed.contains(units[position]) else {
            return skipOptional(element, advanced, position)
        }

        // `<hn>` render bằng bảng phiên âm; bảng chưa nạp thì token không có gì để trả ⇒ coi như không
        // khớp, đúng chính sách của `<hv>` (`QuickTranslationDictionaryToken.isUsable`).
        if kind == .hanNumeral, !dictionaries.isUsable(.hanViet) {
            return skipOptional(element, advanced, position)
        }

        let allowed: Set<UInt16>
        if kind == .chinese || kind == .digitwise {
            if QuickTranslationNumberFormatter.asciiDigitsUnits.contains(units[position]) {
                allowed = baseAllowed.intersection(QuickTranslationNumberFormatter.asciiDigitsUnits)
            } else {
                allowed = baseAllowed.subtracting(QuickTranslationNumberFormatter.asciiDigitsUnits)
            }
        } else {
            allowed = baseAllowed
        }

        // Guard bên trái: ký tự ngay trước match thuộc cùng lớp số ⇒ token đang nuốt phần giữa của
        // một chuỗi số dài hơn. Ngoại lệ: nếu ký tự bên trái thuộc Name riêng thì nó là ranh giới tên chứ
        // không phải phần tiếp nối của số.
        if element.guardsLeft, position > 0,
           !bookNameOccupiedIndices.contains(position - 1),
           allowed.contains(units[position - 1]) {
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
            if kind == .magnitude, !QuickTranslationMagnitudeFormatter.isMagnitudeCandidate(value) {
                candidate -= 1
                continue
            }
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
            case .hanNumeral:
                rendered = dictionaries.hanVietReading(for: value)
            case .magnitude:
                rendered = QuickTranslationNumberFormatter.renderMagnitude(value, leadsPattern: element.leadsPattern)
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

    /// `<any>`: thử độ dài **dài → ngắn** có lùi như `walkNumeral`; từ 1.3.686 nuốt **mọi** đơn vị UTF-16
    /// kể cả dấu câu và khoảng trắng, chỉ dừng ở xuống dòng `\n`/`\r`. Capture trả nguyên văn; chuỗi sau
    /// rewrite vẫn được tách từ và dịch từ điển như phần còn lại của dòng.
    ///
    /// Hai ràng buộc mà token số không cần:
    /// - Không bắt đầu hay kết thúc **giữa** một cặp surrogate (chữ Hán mở rộng B+ chiếm 2 đơn vị).
    /// - Được nuốt **trọn** Name riêng (capture mang `allowsEnclosedNames`, engine chấp nhận), nhưng không
    ///   được bắt đầu hay kết thúc **giữa** một Name: engine bỏ lượt khớp đó **sau** khi matcher trả về,
    ///   lúc ấy không còn lùi về độ dài khác được. Chỉ có tập vị trí bị chiếm nên hai Name dán liền nhau bị
    ///   coi là một vùng — không cắt được ở khe giữa hai Name (thận trọng, không sinh match bị engine bỏ).
    ///
    /// Hiệu năng: nếu phần tử **ngay sau** `<any>` trong cùng dãy là chữ cố định, chỉ những độ dài để lại
    /// đúng chữ đó ở ngay sau mới được thử — không đi bộ cả 50–100 độ dài cho mỗi vị trí. Token ngoặc ngay
    /// sau (1.3.692) cũng vậy: chỉ thử độ dài mà ký tự kế tiếp là ngoặc hợp lệ cho token đó.
    private func walkAnyRun(
        _ element: QuickTranslationRuleElement,
        _ advanced: [Frame],
        _ position: Int
    ) -> Int? {
        guard position < units.count, !splitsSurrogatePair(at: position), !isInsideBookName(at: position) else {
            return skipOptional(element, advanced, position)
        }

        let limit = min(element.maxLength, units.count - position)
        var run = 0
        while run < limit, !QuickTranslationRuleLineAnchor.isLineBreak(units[position + run]) {
            run += 1
        }

        let nextLiteral = followingLiteral(in: advanced)
        let nextBracketUnits = followingBracketUnits(in: advanced)
        let saved = captures
        var candidate = run
        while candidate >= element.minLength {
            let end = position + candidate
            candidate -= 1
            if splitsSurrogatePair(at: end) || isInsideBookName(at: end) { continue }
            if let nextLiteral, !hasLiteral(nextLiteral, at: end) { continue }
            if let nextBracketUnits, !(end < units.count && nextBracketUnits.contains(units[end])) { continue }
            let range = NSRange(location: position, length: end - position)
            store(text.substring(with: range), sourceRange: range, for: element, allowsEnclosedNames: true)
            if let matchEnd = walk(advanced, end) { return matchEnd }
            captures = saved
        }

        return skipOptional(element, advanced, position)
    }

    /// `true` khi `index` rơi **giữa** một vùng Name riêng (cả ký tự trước lẫn ký tự tại `index` đều bị
    /// Name chiếm) — `<any>` không được bắt đầu hay kết thúc ở đó.
    private func isInsideBookName(at index: Int) -> Bool {
        index > 0 && index < units.count
            && bookNameOccupiedIndices.contains(index) && bookNameOccupiedIndices.contains(index - 1)
    }

    /// `true` khi `index` rơi giữa high và low của một cặp surrogate.
    private func splitsSurrogatePair(at index: Int) -> Bool {
        index > 0 && index < units.count
            && UTF16.isLeadSurrogate(units[index - 1]) && UTF16.isTrailSurrogate(units[index])
    }

    /// Token optional vắng mặt ⇒ capture rỗng, `{i}` render chuỗi rỗng; `sourceRange` là `nil` vì
    /// không có ký tự nguồn nào bị nuốt.
    func skipOptional(
        _ element: QuickTranslationRuleElement,
        _ advanced: [Frame],
        _ position: Int
    ) -> Int? {
        guard element.isOptional else { return nil }
        store("", sourceRange: nil, for: element)
        return walk(advanced, position)
    }

    func store(
        _ value: String,
        sourceRange: NSRange?,
        for element: QuickTranslationRuleElement,
        allowsEnclosedNames: Bool = false
    ) {
        guard let index = element.captureIndex, index < captures.count else { return }
        let text = element.renderedMeaning(value) // `<VP>`… ép viết hoa nghĩa (1.3.761)
        captures[index] = Capture(text: text, sourceRange: sourceRange, allowsEnclosedNames: allowsEnclosedNames)
    }
}
