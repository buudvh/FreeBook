import Foundation

/// Áp bộ rule dịch lên một chuỗi Trung: chèn **sau** Phồn thể → Giản thể và **trước** tokenize.
///
/// Từ 1.3.274 engine trộn **hai** bộ rule trong cùng một lượt: bộ **riêng của truyện**
/// (`scopeRank = 0`) và bộ **chung** (`scopeRank = 1`). Hai bộ được thu match riêng rồi `select`
/// **một** lần trên tập hợp nhất — không dựng `literalIndex` gộp cho từng truyện, vì index của bộ
/// 17k dòng là cấu trúc lớn còn bộ riêng chỉ vài chục rule.
///
/// Thứ tự chọn match: `start` **luôn** đầu, `sourceLine` **luôn** cuối, bốn tiêu chí giữa
/// (`literalLength`, `wildcardCapacity`, độ dài match, `scopeRank`) lấy thứ tự và chiều từ
/// `QuickTranslationRulePriorityConfiguration` — cấu hình được cho toàn app và riêng từng truyện.
/// Mặc định từ 1.3.300 là preset **Ưu tiên độ dài**, không còn trùng `executeRules` của reference
/// (preset "Như engine gốc" giữ hành vi cũ).
///
/// Ba ràng buộc giữ nguyên theo reference: **không cascade** (chuỗi Việt vừa render không được đưa
/// lại cho rule), **không exhaustive match** (mỗi rule chỉ phát match trái → phải), và **không**
/// `trim()` input (trim là lệch range).
public enum QuickTranslationRuleEngine {
    /// Ô thử nhanh luôn bỏ qua công tắc tổng, nhưng có thể chọn phản ánh hoặc bỏ qua cấu hình token.
    public enum PreviewMode: CaseIterable, Hashable, Sendable {
        case respectTokenConfiguration
        case ignoreTokenConfiguration
    }


    /// `internal` chứ không `private`: `QuickTranslationRuleDiagnostics` phải dùng **đúng** hàm
    /// `select` này, không được cài lại 6 tiêu chí ưu tiên ở chỗ thứ hai.
    struct Found {
        let start: Int
        let length: Int
        let literalLength: Int
        let wildcardCapacity: Int
        let scopeRank: Int
        let sourceLine: Int
        let rendered: String
        /// Index của rule trong `snapshot.rules` của **bộ tương ứng với `scopeRank`**.
        let ruleIndex: Int
        let captures: [QuickTranslationRuleMatcher.Capture]

        /// Giá trị của một tiêu chí phá tranh chấp. `select` đọc qua đây để thứ tự tiêu chí là **dữ
        /// liệu** (cấu hình) chứ không phải chuỗi `if` cứng.
        func metric(for key: QuickTranslationRulePriorityConfiguration.Key) -> Int {
            switch key {
            case .literalLength: return literalLength
            case .wildcardCapacity: return wildcardCapacity
            case .matchLength: return length
            case .scopeRank: return scopeRank
            }
        }
    }

    /// Memo nhỏ: pipeline gọi `rewrite` hai lần cho cùng một chuỗi (một lần để dịch, một lần để dựng
    /// span), không có memo là chạy engine hai lượt.
    ///
    /// `maxEntries` phải **lớn hơn số đoạn của một chương** (chương dài vài trăm đoạn): để 64 thì memo
    /// thrash ngay trong một lượt dựng chương, tức lượt gọi thứ hai luôn trượt. Trần bộ nhớ thật vẫn là
    /// `maxCost` — nâng `maxEntries` không nới bộ nhớ.
    private static let cache = TranslationMemo<QuickTranslationRewriteResult>(maxEntries: 2048, maxCost: 2 * 1024 * 1024)

    /// `nil` khi công tắc tắt hoặc **cả hai** bộ đều không có rule — bên gọi giữ nguyên đường dịch cũ.
    public static func rewrite(_ text: String, bookId: String?) -> QuickTranslationRewriteResult? {
        guard !text.isEmpty else { return nil }
        let context = TranslationReadContext.current ?? TranslationReadContext.capture(bookId: bookId)
        guard context.rulesEnabled else { return nil }
        let globalSnapshot = nonEmpty(context.globalRules)
        let bookSnapshot = nonEmpty(context.bookRules)
        guard globalSnapshot != nil || bookSnapshot != nil else { return nil }

        let tokenConfiguration = context.tokens
        let priority = context.priority

        // Khoá mang generation của **cả hai** bộ: hai truyện khác nhau đã khác `bookId`, nhưng cùng
        // một truyện sau khi sửa bộ riêng phải là khoá khác. `priority.signature` cũng phải có mặt —
        // đổi thứ tự ưu tiên mà không đổi khoá là cache cũ tiếp tục trả kết quả của thứ tự cũ.
        let key = "\(context.generation)|\(globalSnapshot?.generation ?? 0)|\(bookSnapshot?.generation ?? 0)"
            + "|\(tokenConfiguration.signature)|\(priority.signature)|\(bookId ?? "global")|\(text.md5())"
        let lookup = cache.lookup(key)
        if let cached = lookup.value { return cached }

        let result = TranslationReadContext.$current.withValue(context) { execute(
            text,
            bookSnapshot: bookSnapshot,
            globalSnapshot: globalSnapshot,
            bookId: bookId,
            tokenConfiguration: tokenConfiguration,
            priority: priority
        ) }
        if !Task.isCancelled, context.isCurrent {
            cache.insert(result, key: key, bookId: bookId,
                         cost: result.text.utf16.count * 4 + text.utf16.count * 64, ticket: lookup.ticket)
        }
        return result
    }

    public static func clearCache(bookId: String? = nil) {
        cache.invalidate(bookId: bookId)
    }

    /// Dùng cho ô thử nhanh ở màn hình quản lý: luôn bỏ qua công tắc tổng và không dùng memo, nhưng
    /// **vẫn tôn trọng file tắt** — nếu không nó nói khác kết quả thật của Reader.
    public static func preview(
        _ text: String,
        bookId: String? = nil,
        mode: PreviewMode = .respectTokenConfiguration
    ) -> QuickTranslationRewriteResult? {
        guard !text.isEmpty else { return nil }
        let globalSnapshot = nonEmpty(QuickTranslationRuleStore.shared.currentSnapshot)
        let bookSnapshot = nonEmpty(QuickTranslationRuleBookStore.shared.snapshot(for: bookId))
        guard globalSnapshot != nil || bookSnapshot != nil else { return nil }

        let tokenConfiguration: QuickTranslationRuleTokenSettings.Configuration
        switch mode {
        case .respectTokenConfiguration:
            tokenConfiguration = QuickTranslationBookEngineConfigStore.shared
                .tokenConfiguration(bookId: bookId)
        case .ignoreTokenConfiguration:
            tokenConfiguration = .allEnabled
        }
        return execute(
            text,
            bookSnapshot: bookSnapshot,
            globalSnapshot: globalSnapshot,
            bookId: bookId,
            tokenConfiguration: tokenConfiguration,
            priority: QuickTranslationBookEngineConfigStore.shared.priorityConfiguration(bookId: bookId)
        )
    }

    private static func nonEmpty(_ snapshot: QuickTranslationRuleSnapshot?) -> QuickTranslationRuleSnapshot? {
        guard let snapshot, !snapshot.rules.isEmpty else { return nil }
        return snapshot
    }

    // MARK: - Thi hành

    private static func execute(
        _ text: String,
        bookSnapshot: QuickTranslationRuleSnapshot?,
        globalSnapshot: QuickTranslationRuleSnapshot?,
        bookId: String?,
        tokenConfiguration: QuickTranslationRuleTokenSettings.Configuration,
        priority: QuickTranslationRulePriorityConfiguration.Configuration
    ) -> QuickTranslationRewriteResult {
        let nsText = text as NSString
        let (bookNameRanges, bookNameOccupiedIndices) = scanBookNameOccupiedIndices(text: text, bookId: bookId)
        let matcher = QuickTranslationRuleMatcher(
            text: text,
            dictionaries: QuickTranslationDictionaryToken.resolve(bookId: bookId),
            bookNameOccupiedIndices: bookNameOccupiedIndices
        )
        let disable = TranslationReadContext.current?.disabledRules ?? QuickTranslationRuleDisableStore.shared.snapshot(bookId: bookId)

        var found: [Found] = []
        // Bộ riêng đi trước cho dễ đọc log; thứ tự thu match không ảnh hưởng kết quả vì `select`
        // sắp xếp lại toàn bộ.
        found += collectFound(
            text: text,
            snapshot: bookSnapshot,
            scopeRank: 0,
            matcher: matcher,
            tokenConfiguration: tokenConfiguration,
            disable: disable,
            includesDisabled: false,
            bookNameRanges: bookNameRanges,
            bookNameOccupiedIndices: bookNameOccupiedIndices
        )
        found += collectFound(
            text: text,
            snapshot: globalSnapshot,
            scopeRank: 1,
            matcher: matcher,
            tokenConfiguration: tokenConfiguration,
            disable: disable,
            includesDisabled: false,
            bookNameRanges: bookNameRanges,
            bookNameOccupiedIndices: bookNameOccupiedIndices
        )

        guard !found.isEmpty else { return passthrough(text, length: nsText.length) }
        return assemble(selected: select(from: found, priority: priority), text: text, nsText: nsText)
    }

    /// Thu **mọi** match của một bộ rule. `includesDisabled == true` chỉ dùng cho màn chẩn đoán:
    /// nó cần thấy cả rule đang tắt và rule bị token tắt để hiện ra cho người dùng bật lại.
    static func collectFound(
        text: String,
        snapshot: QuickTranslationRuleSnapshot?,
        scopeRank: Int,
        matcher: QuickTranslationRuleMatcher,
        tokenConfiguration: QuickTranslationRuleTokenSettings.Configuration,
        disable: QuickTranslationRuleDisableStore.Snapshot,
        includesDisabled: Bool,
        bookNameRanges: [NSRange] = [],
        bookNameOccupiedIndices: Set<Int> = [],
        notesComplexRules: Bool = true,
        onTooComplex: ((Int, Int) -> Void)? = nil
    ) -> [Found] {
        guard let snapshot, !snapshot.rules.isEmpty else { return [] }
        let units = Array(text.utf16)
        let candidates = snapshot.literalIndex.candidates(in: units)
        guard !candidates.isEmpty else { return [] }

        var found: [Found] = []
        for candidate in candidates {
            if Task.isCancelled { return [] }
            let rule = snapshot.rules[candidate.ruleIndex]
            if !includesDisabled {
                guard rule.isEnabled(for: tokenConfiguration) else { continue }
                guard !disable.isDisabled(pattern: rule.pattern, scopeRank: scopeRank) else { continue }
            }
            var cursor = 0
            for start in candidate.starts where start >= cursor {
                if Task.isCancelled { return [] }
                // Không cho rule bắt đầu từ giữa chừng một Name riêng (trừ điểm bắt đầu của Name)
                if !includesDisabled, bookNameOccupiedIndices.contains(start), !bookNameRanges.contains(where: { $0.location == start }) {
                    continue
                }
                guard let match = matcher.match(rule, at: start) else {
                    if matcher.didExceedStepCap {
                        if notesComplexRules {
                            QuickTranslationRuleStore.shared.noteComplexRule(sourceLine: rule.sourceLine)
                        }
                        onTooComplex?(candidate.ruleIndex, start)
                        break
                    }
                    continue
                }
                let hasConflict = ruleMatchConflictsWithBookNames(
                    matchStart: match.start,
                    matchLength: match.length,
                    captures: match.captures,
                    bookNameRanges: bookNameRanges
                )
                if !includesDisabled && hasConflict {
                    // Match cắt vào Name riêng -> bỏ qua và không đẩy cursor để các start kế tiếp sau Name vẫn được thử
                    continue
                }
                found.append(Found(
                    start: match.start,
                    length: match.length,
                    literalLength: rule.literalLength,
                    wildcardCapacity: rule.wildcardCapacity,
                    scopeRank: scopeRank,
                    sourceLine: rule.sourceLine,
                    rendered: rule.render(captures: match.captureTexts),
                    ruleIndex: candidate.ruleIndex,
                    captures: match.captures
                ))
                cursor = hasConflict ? (match.start + 1) : (match.start + max(1, match.length))
            }
        }
        return found
    }

    /// Sort một lần rồi quét một pass tuyến tính. Reference gọi `matches.filter(...)` trong vòng
    /// `while` (bậc hai) nhưng kết quả giống hệt.
    ///
    /// **Hai đầu bị khoá, giữa thì theo cấu hình.** `start` luôn là khoá chính vì vòng quét bên dưới
    /// dựa vào nó (xem `QuickTranslationRulePriorityConfiguration`), và `sourceLine` luôn là khoá
    /// cuối vì nó là thứ duy nhất bảo đảm kết quả xác định. Bốn tiêu chí ở giữa lấy thứ tự và chiều
    /// từ `priority` — mọi hoán vị đều là strict weak ordering hợp lệ nên `sorted(by:)` an toàn.
    static func select(
        from found: [Found],
        priority: QuickTranslationRulePriorityConfiguration.Configuration = .default
    ) -> [Found] {
        let keys = priority.order
        let sorted = found.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            for key in keys {
                let left = lhs.metric(for: key)
                let right = rhs.metric(for: key)
                guard left != right else { continue }
                return priority.isDescending(key) ? left > right : left < right
            }
            return lhs.sourceLine < rhs.sourceLine
        }

        var selected: [Found] = []
        var cursor = 0
        for match in sorted where match.start >= cursor {
            selected.append(match)
            cursor = match.start + max(1, match.length)
        }
        return selected
    }

    private static func assemble(
        selected: [Found],
        text: String,
        nsText: NSString
    ) -> QuickTranslationRewriteResult {
        var output = ""
        var segments: [QuickTranslationRewriteResult.Segment] = []
        var cursor = 0
        var outputLength = 0

        func appendPassthrough(upTo end: Int) {
            guard end > cursor else { return }
            let range = NSRange(location: cursor, length: end - cursor)
            let piece = nsText.substring(with: range)
            output += piece
            let pieceLength = (piece as NSString).length
            segments.append(QuickTranslationRewriteResult.Segment(
                sourceRange: range,
                outputRange: NSRange(location: outputLength, length: pieceLength),
                sourceLine: nil
            ))
            outputLength += pieceLength
            cursor = end
        }

        for (index, match) in selected.enumerated() {
            appendPassthrough(upTo: match.start)
            var rendered = match.rendered

            // 1. Tự động chèn khoảng trắng phía trước token rule nếu cần
            if needsLeadingSeparator(output: output, rendered: rendered) {
                rendered = " " + rendered
            }

            // 2. Tự động chèn khoảng trắng phía sau token rule nếu cần
            let nextChar: Character?
            if index + 1 < selected.count, selected[index + 1].start == match.start + match.length {
                nextChar = selected[index + 1].rendered.first
            } else if match.start + match.length < nsText.length {
                nextChar = (nsText.substring(from: match.start + match.length)).first
            } else {
                nextChar = nil
            }

            if needsTrailingSeparator(rendered: rendered, nextChar: nextChar) {
                rendered = rendered + " "
            }

            output += rendered
            let renderedLength = (rendered as NSString).length
            segments.append(QuickTranslationRewriteResult.Segment(
                sourceRange: NSRange(location: match.start, length: match.length),
                outputRange: NSRange(location: outputLength, length: renderedLength),
                sourceLine: match.sourceLine
            ))
            outputLength += renderedLength
            cursor = match.start + match.length
        }
        appendPassthrough(upTo: nsText.length)

        return QuickTranslationRewriteResult(
            text: output,
            segments: segments,
            appliedRuleCount: selected.count
        )
    }

    private static func needsLeadingSeparator(output: String, rendered: String) -> Bool {
        guard let lastChar = output.last, let firstChar = rendered.first else {
            return false
        }
        if lastChar.isWhitespace || firstChar.isWhitespace {
            return false
        }
        let noSpaceAfter: Set<Character> = ["“", "‘", "\"", "'", "(", "[", "{", "《", "〈", "「", "『", "【"]
        return !noSpaceAfter.contains(lastChar)
    }

    private static func needsTrailingSeparator(rendered: String, nextChar: Character?) -> Bool {
        guard let lastChar = rendered.last, let nextChar else {
            return false
        }
        if lastChar.isWhitespace || nextChar.isWhitespace {
            return false
        }
        let noSpaceBefore: Set<Character> = [
            "”", "’", "\"", "'", ")", "]", "}", "》", "〉", "」", "』", "】",
            "，", "。", "！", "？", "、", "；", "：",
            ",", ".", "!", "?", ";", ":"
        ]
        return !noSpaceBefore.contains(nextChar)
    }

    private static func passthrough(_ text: String, length: Int) -> QuickTranslationRewriteResult {
        QuickTranslationRewriteResult(
            text: text,
            segments: [QuickTranslationRewriteResult.Segment(
                sourceRange: NSRange(location: 0, length: length),
                outputRange: NSRange(location: 0, length: length),
                sourceLine: nil
            )],
            appliedRuleCount: 0
        )
    }
}
