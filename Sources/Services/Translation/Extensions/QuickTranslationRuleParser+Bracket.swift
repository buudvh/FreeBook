import Foundation

/// Token ngoặc `<[>` / `<]>` của DSL rule dịch (1.3.692) và bước ghép cặp chạy sau khi dựng xong AST.
///
/// Ngoặc **không sinh `{i}`** (như neo dòng): thêm `<[>`/`<]>` vào mẫu không làm số `{i}` của token khác
/// đổi. Ký tự mở mà `<[>` bắt được giữ ở một **ô ẩn** (`bracketSlot`) đặt **sau** mọi ô `{i}` trong mảng
/// capture của matcher; `<]>` đọc lại ô đó (`bracketPartnerSlot`) để đòi đúng ngoặc đóng và đoạn giữa
/// cân bằng. Vì vậy `QuickTranslationParsedRule.slotCount = captureCount + số <[>`.
///
/// Bộ ngoặc là **dữ liệu** của matcher (`QuickTranslationRuleBracketSet`), parser không đọc nó: `<` `>`
/// `{` `}` nằm trong bộ ngoặc không làm parser hiểu nhầm token hay `{i}`.
///
/// Tách khỏi `QuickTranslationRuleParser.swift` để file gốc không vượt trần 400 dòng.
extension QuickTranslationRuleParser {
    private typealias TokenKind = QuickTranslationRuleTokenSettings.Kind

    // MARK: - Token không sinh {i}

    /// `spec` là phần giữa `<` và `>` (vd `[`, `START`, `n:1-6`). `true` khi tên token nhắc tới một token
    /// **không sinh `{i}`** — neo dòng (`START`/`END`, cách viết cũ `^`/`$`) hoặc ngoặc (`[`/`]`) — kể cả cách
    /// viết sai như `<[|n>`, để màn sửa rule (`QuickTranslationRuleDraftAnalyzer.segments`) đếm chip giống
    /// hệt cách parser cấp số.
    public static func isUncapturedTokenSpec(_ spec: String) -> Bool {
        tokenSpecNames(spec).names.contains { TokenKind.kind(forTokenName: $0)?.isUncaptured == true }
    }

    /// Tách `spec` đúng như `parseToken`: bỏ phần `#min-max` (1.3.701), tên trước dấu `:`, ngăn bằng `|`, bỏ khoảng
    /// trắng hai đầu.
    static func tokenSpecNames(_ spec: String) -> (names: [String], hasLength: Bool) {
        let parts = QuickTranslationRuleValueRange.split(spec: spec).head.components(separatedBy: ":")
        let names = parts[0].components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        return (names, parts.count > 1)
    }

    /// Neo dòng hoặc ngoặc; ném lỗi khi viết sai; `nil` khi `spec` không dính tới hai loại này để
    /// `parseToken` đi tiếp đường token thường (có cấp số `{i}`).
    static func parseUncapturedToken(spec: String, isOptional: Bool) throws -> QuickTranslationRuleElement? {
        try rejectValueRangeOnUncapturedToken(spec)
        if let anchor = try parseLineAnchor(spec: spec, isOptional: isOptional) { return anchor }
        return try parseBracketToken(spec: spec, isOptional: isOptional)
    }

    /// `<[>` / `<]>` (nhận `?` = có thể vắng). Ghép `|` hay ghi `:min-max` ⇒ `UNKNOWN_TOKEN_NAME` kèm câu
    /// giải thích, như neo dòng.
    private static func parseBracketToken(spec: String, isOptional: Bool) throws -> QuickTranslationRuleElement? {
        let parsed = tokenSpecNames(spec)
        guard let kind = parsed.names.compactMap(TokenKind.kind(forTokenName:)).first(where: \.isBracket) else {
            return nil
        }
        guard parsed.names.count == 1 else {
            throw ParseError(code: .unknownTokenName, message: "Token \(kind.syntax) không ghép được với token khác bằng dấu |")
        }
        guard !parsed.hasLength else {
            throw ParseError(
                code: .unknownTokenName,
                message: "Token \(kind.syntax) khớp đúng một ký tự ngoặc nên không nhận độ dài :min-max"
            )
        }
        return QuickTranslationRuleElement(
            kind: kind == .openBracket ? .openBracket : .closeBracket,
            sourceTokenKinds: [kind],
            minLength: 1,
            maxLength: 1,
            isOptional: isOptional
        )
    }

    // MARK: - Dựng một rule + ghép cặp ngoặc

    /// Mẫu → AST (đánh số `{i}`) → ghép cặp ngoặc → `QuickTranslationParsedRule`. Ô ẩn của `<[>` được cấp
    /// **sau** khi đếm xong `{i}` (`captureCount + k`, k theo thứ tự nguồn).
    static func makeParsedRule(
        sourceLine: Int,
        rawLine: String,
        pattern: String,
        replacement: String
    ) throws -> QuickTranslationParsedRule {
        var captureCount = 0
        var elements = try parseElements(Array(pattern), captureCount: &captureCount)
        var nextSlot = captureCount
        var openSlots: [Int] = []
        assignBracketSlots(in: &elements, nextSlot: &nextSlot, openSlots: &openSlots)
        return QuickTranslationParsedRule(
            sourceLine: sourceLine,
            rawLine: rawLine,
            pattern: pattern,
            replacement: replacement,
            elements: elements,
            captureCount: captureCount,
            slotCount: nextSlot
        )
    }

    /// Ghép mỗi `<]>` với `<[>` gần nhất còn mở theo **thứ tự nguồn**, bằng một ngăn xếp ô (`openSlots`).
    ///
    /// Nhóm `( | )`: mỗi nhánh bắt đầu từ **cùng** ngăn xếp lúc vào nhóm (nên `<[>(a<]>|b<]>)` cho cả hai `<]>`
    /// cùng cặp), số ô thì cấp tiếp liền qua mọi nhánh (mỗi `<[>` một ô riêng). Sau nhóm đi tiếp với ngăn
    /// xếp **dài nhất** trong các nhánh — giữ lại `<[>` chưa đóng cho `<]>` phía sau, như `(<[>a|b)<]>`. Ở
    /// lượt khớp mà `<[>` đó nằm trong nhánh không khớp thì ô của nó trống và `<]>` nhận mọi ngoặc đóng.
    private static func assignBracketSlots(
        in elements: inout [QuickTranslationRuleElement],
        nextSlot: inout Int,
        openSlots: inout [Int]
    ) {
        for index in elements.indices {
            switch elements[index].kind {
            case .openBracket:
                elements[index].bracketSlot = nextSlot
                openSlots.append(nextSlot)
                nextSlot += 1
            case .closeBracket:
                elements[index].bracketPartnerSlot = openSlots.popLast()
            case .group(var alternatives):
                let entry = openSlots
                var longest = entry
                for branch in alternatives.indices {
                    var branchSlots = entry
                    assignBracketSlots(in: &alternatives[branch], nextSlot: &nextSlot, openSlots: &branchSlots)
                    if branch == 0 || branchSlots.count > longest.count { longest = branchSlots }
                }
                openSlots = longest
                elements[index].kind = .group(alternatives)
            case .literal, .numeral, .chapterLabel, .dictionary, .anyRun, .lineStart, .lineEnd:
                continue
            }
        }
    }
}
