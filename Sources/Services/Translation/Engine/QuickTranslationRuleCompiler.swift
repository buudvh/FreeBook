import Foundation

/// AST đã parse → dạng thi hành, kèm validate theo hợp đồng trong header file rule.
///
/// Chính sách phân loại lỗi: **hard** thì rule đó không vào engine; **warning** thì vẫn nạp. Luồng
/// import/CRUD canonical sẽ bỏ dòng hỏng rồi ghi lại phần hợp lệ, không chặn cả file.
public enum QuickTranslationRuleCompiler {
    public struct Result {
        public var rules: [QuickTranslationCompiledRule] = []
        public var issues: [QuickTranslationRuleIssue] = []

        public var hasHardError: Bool {
            issues.contains { $0.severity == .hard }
        }
    }

    /// Literal chỉ gồm những ký tự cực phổ biến ⇒ prefilter gần như vô dụng, dễ khớp bừa.
    private static let weakAnchorUnits: Set<UInt16> = Set("的了是不存在上下个個".utf16)

    /// `scopeRank` đi thẳng vào mọi rule của lượt compile này: 0 = bộ **riêng** truyện, 1 = bộ
    /// **chung**. Nó là tiêu chí ưu tiên thứ 5 trong `QuickTranslationRuleEngine.select`, đứng ngay
    /// trước `sourceLine`, nên rule riêng thắng rule chung khi trùng mọi tiêu chí trước đó.
    public static func compile(
        _ parsed: QuickTranslationRuleParser.Result,
        scopeRank: Int = 1
    ) -> Result {
        var result = Result()
        result.issues = parsed.issues
        var seenPatterns: [String: Int] = [:]

        for rule in parsed.rules {
            var issues: [QuickTranslationRuleIssue] = []

            func note(_ code: QuickTranslationRuleIssue.Code, _ message: String) {
                issues.append(QuickTranslationRuleIssue(
                    sourceLine: rule.sourceLine,
                    code: code,
                    message: message,
                    rawLine: rule.rawLine
                ))
            }

            let template = parseTemplate(rule.replacement)
            let referenced = Set(template.compactMap { segment -> Int? in
                if case .capture(let index) = segment { return index }
                return nil
            })

            for index in referenced.sorted() where index >= rule.captureCount {
                note(.invalidRefIndex, "Tham chiếu {\(index)} vượt quá số token (\(rule.captureCount))")
            }
            for index in 0..<rule.captureCount where !referenced.contains(index) {
                note(.unusedCapture, "Token thứ \(index) chỉ dùng để khớp, không xuất ra bản dịch (không có {\(index)})")
            }

            if !hasAnchor(rule.elements) {
                note(.noLiteralAnchor, "Mẫu không có ký tự thường nào làm neo")
            }

            if let previous = seenPatterns[rule.pattern] {
                note(.duplicatePattern, "Trùng mẫu với dòng \(previous); dòng sớm hơn thắng ở runtime")
            } else {
                seenPatterns[rule.pattern] = rule.sourceLine
            }

            if hasBareLiteralSpace(rule.elements) {
                note(.literalSpaceInPattern, "Mẫu có khoảng trắng làm ký tự thường; văn bản Trung hầu như không có")
            }

            if hasConsecutiveTokens(rule.elements) {
                note(.multipleConsecutiveWildcards, "Hai token dán nhau: dựa hoàn toàn vào backtracking để chia chuỗi")
            }

            var elements = rule.elements
            applyBoundaryGuards(&elements)

            let literal = requiredLiteral(of: elements)
            if !literal.units.isEmpty, literal.units.allSatisfy({ weakAnchorUnits.contains($0) }) {
                note(.weakAnchor, "Neo chỉ gồm ký tự cực phổ biến, dễ khớp bừa")
            }

            let dictionaryKinds = collectDictionaryKinds(elements)
            let tokenKinds = collectTokenKinds(elements)
            result.issues.append(contentsOf: issues)

            guard !issues.contains(where: { $0.severity == .hard }) else { continue }

            result.rules.append(QuickTranslationCompiledRule(
                sourceLine: rule.sourceLine,
                pattern: rule.pattern,
                replacement: rule.replacement,
                elements: elements,
                template: template,
                captureCount: rule.captureCount,
                literalLength: literalLength(of: elements),
                wildcardCapacity: wildcardCapacity(of: elements),
                requiredLiteral: literal.units,
                requiredLiteralPrefixMin: literal.prefixMin,
                requiredLiteralPrefixMax: literal.prefixMax,
                requiredDictionaryKinds: dictionaryKinds,
                requiredTokenKinds: tokenKinds,
                scopeRank: scopeRank
            ))
        }

        return result
    }

    // MARK: - RHS

    /// `internal` chứ không `private`: màn thêm/sửa rule phải hỏi **đúng** hàm này "bản dịch đang
    /// tham chiếu `{i}` nào" để chấm điểm bản nháp. Cài lại vòng quét `{…}` ở chỗ thứ hai là mở đường
    /// cho hai nơi hiểu khác nhau về cùng một RHS.
    internal static func parseTemplate(_ replacement: String) -> [QuickTranslationCompiledRule.TemplateSegment] {
        var segments: [QuickTranslationCompiledRule.TemplateSegment] = []
        var text = ""
        let characters = Array(replacement)
        var cursor = 0

        while cursor < characters.count {
            if characters[cursor] == "{",
               let close = characters[cursor...].firstIndex(of: "}"),
               close > cursor + 1 {
                let digits = String(characters[(cursor + 1)..<close])
                if let index = Int(digits), digits.allSatisfy({ $0.isASCII && $0.isNumber }) {
                    if !text.isEmpty {
                        segments.append(.text(text))
                        text = ""
                    }
                    segments.append(.capture(index))
                    cursor = close + 1
                    continue
                }
            }
            text.append(characters[cursor])
            cursor += 1
        }

        if !text.isEmpty { segments.append(.text(text)) }
        return segments
    }

    // MARK: - Chỉ số ưu tiên

    private static func literalLength(of elements: [QuickTranslationRuleElement]) -> Int {
        var total = 0
        for element in elements {
            switch element.kind {
            case .literal(let units):
                total += units.count
            case .group(let alternatives):
                guard !element.isOptional else { continue }
                total += alternatives.map { literalLength(of: $0) }.max() ?? 0
            case .numeral, .chapterLabel, .dictionary:
                continue
            }
        }
        return total
    }

    private static func wildcardCapacity(of elements: [QuickTranslationRuleElement]) -> Int {
        var total = 0
        for element in elements {
            switch element.kind {
            case .numeral, .chapterLabel, .dictionary:
                total += element.maxLength
            case .group(let alternatives):
                total += alternatives.map { wildcardCapacity(of: $0) }.max() ?? 0
            case .literal:
                continue
            }
        }
        return total
    }

    // MARK: - Neo prefilter

    private static func requiredLiteral(
        of elements: [QuickTranslationRuleElement]
    ) -> (units: [UInt16], prefixMin: Int, prefixMax: Int) {
        var best: [UInt16] = []
        var bestMin = 0
        var bestMax = 0
        var runningMin = 0
        var runningMax = 0

        for element in elements {
            if case .literal(let units) = element.kind, !element.isOptional, units.count > best.count {
                best = units
                bestMin = runningMin
                bestMax = runningMax
            }
            runningMin += element.minimumWidth
            runningMax += element.maximumWidth
        }

        return (best, bestMin, bestMax)
    }

    private static func hasAnchor(_ elements: [QuickTranslationRuleElement]) -> Bool {
        for element in elements {
            switch element.kind {
            case .literal(let units):
                if !units.isEmpty { return true }
            case .group(let alternatives):
                guard !element.isOptional, !alternatives.isEmpty else { continue }
                if alternatives.allSatisfy({ hasAnchor($0) }) { return true }
            case .numeral, .chapterLabel, .dictionary:
                continue
            }
        }
        return false
    }

    /// Khoảng trắng **bắt buộc** trong mẫu: chỉ tính literal ở mức ngoài cùng và không optional.
    ///
    /// Không được tìm chuỗi `" "` trên `rule.pattern` thô: `( )?` là idiom "khoảng trắng tuỳ chọn"
    /// và có ở 1.023/1.177 rule của `rule-aio.txt` — tìm thô sẽ sinh hơn nghìn cảnh báo rác, chôn
    /// mất cảnh báo thật (`<n:1-6>…<y:1-4> km`, nơi space là literal trần và làm rule gần như không
    /// bao giờ khớp).
    private static func hasBareLiteralSpace(_ elements: [QuickTranslationRuleElement]) -> Bool {
        for element in elements where !element.isOptional {
            guard case .literal(let units) = element.kind else { continue }
            if units.contains(0x0020) || units.contains(0x3000) { return true }
        }
        return false
    }

    private static func hasConsecutiveTokens(_ elements: [QuickTranslationRuleElement]) -> Bool {
        var previousWasToken = false
        for element in elements {
            if element.isToken {
                if previousWasToken { return true }
                previousWasToken = true
            } else {
                previousWasToken = false
            }
        }
        return false
    }

    private static func collectDictionaryKinds(
        _ elements: [QuickTranslationRuleElement]
    ) -> [QuickTranslationRuleElement.DictionaryKind] {
        var kinds: [QuickTranslationRuleElement.DictionaryKind] = []
        for element in elements {
            switch element.kind {
            case .dictionary(let list):
                for kind in list where !kinds.contains(kind) { kinds.append(kind) }
            case .group(let alternatives):
                for alternative in alternatives {
                    for kind in collectDictionaryKinds(alternative) where !kinds.contains(kind) {
                        kinds.append(kind)
                    }
                }
            case .literal, .numeral, .chapterLabel:
                continue
            }
        }
        return kinds
    }

    private static func collectTokenKinds(
        _ elements: [QuickTranslationRuleElement]
    ) -> Set<QuickTranslationRuleTokenSettings.Kind> {
        var kinds: Set<QuickTranslationRuleTokenSettings.Kind> = []
        for element in elements {
            kinds.formUnion(element.sourceTokenKinds)
            if case .group(let alternatives) = element.kind {
                for alternative in alternatives {
                    kinds.formUnion(collectTokenKinds(alternative))
                }
            }
        }
        return kinds
    }

    // MARK: - Boundary guard có điều kiện

    /// Header đòi engine tự chặn `<n>/<y>` nuốt **một phần** chuỗi số dài hơn. Bọc vô điều kiện là
    /// giết rule: đo được 82 vị trí token trong bộ rule chuẩn và 49 trong `rule-aio.txt` có literal
    /// cùng lớp số dán sát token (`<n:1-6>万`, `十<y:1>级`, `<n:1-3>十<n:1-3>(万|萬)`…). Nên chỉ guard
    /// khi phần tử liền kề **không** tiếp tục chuỗi số theo lớp ký tự của chính token đó.
    private static func applyBoundaryGuards(_ elements: inout [QuickTranslationRuleElement]) {
        for index in elements.indices {
            guard case .numeral(let kind) = elements[index].kind else { continue }
            let units = QuickTranslationNumberFormatter.units(for: kind)

            let previous = index > 0 ? elements[index - 1] : nil
            let next = index + 1 < elements.count ? elements[index + 1] : nil

            elements[index].guardsLeft = shouldGuard(against: previous, isTrailingSide: true, units: units)
            elements[index].guardsRight = shouldGuard(against: next, isTrailingSide: false, units: units)
        }
    }

    /// `isTrailingSide` = đang xét phần tử **đứng trước** token, nên phải soi ký tự *cuối* của nó.
    private static func shouldGuard(
        against neighbour: QuickTranslationRuleElement?,
        isTrailingSide: Bool,
        units: Set<UInt16>
    ) -> Bool {
        guard let neighbour = neighbour else { return true }

        // Token số khác dán ngay cạnh: cụm token dựa vào backtracking để tự chia chuỗi, guard chỉ
        // đặt ở hai đầu ngoài của cả cụm.
        if case .numeral = neighbour.kind { return false }
        if neighbour.isToken { return false }

        let edge = isTrailingSide ? neighbour.trailingLiteralUnits : neighbour.leadingLiteralUnits
        guard let edge = edge, !edge.isEmpty else { return true }
        // Group "mixed" (một số nhánh mở đầu bằng ký tự lớp số, một số không) ⇒ bỏ guard, chọn hướng
        // bảo toàn rule thay vì hướng siết.
        if edge.contains(where: { units.contains($0) }) { return false }
        // Literal không thuộc lớp số: guard vô hại (ký tự liền kề chính là literal đó) và cần thiết
        // khi nhóm optional vắng mặt.
        return true
    }
}
