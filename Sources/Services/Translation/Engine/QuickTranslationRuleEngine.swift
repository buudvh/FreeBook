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

    private final class CacheEntry {
        let result: QuickTranslationRewriteResult
        init(_ result: QuickTranslationRewriteResult) { self.result = result }
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
    private static let cache: NSCache<NSString, CacheEntry> = {
        let cache = NSCache<NSString, CacheEntry>()
        cache.countLimit = 64
        return cache
    }()

    /// `nil` khi công tắc tắt hoặc **cả hai** bộ đều không có rule — bên gọi giữ nguyên đường dịch cũ.
    public static func rewrite(_ text: String, bookId: String?) -> QuickTranslationRewriteResult? {
        guard !text.isEmpty else { return nil }
        let globalSnapshot = QuickTranslationRuleStore.shared.activeSnapshot
        let bookSnapshot = QuickTranslationRuleBookStore.shared.activeSnapshot(for: bookId)
        guard globalSnapshot != nil || bookSnapshot != nil else { return nil }

        let tokenConfiguration = QuickTranslationBookEngineConfigStore.shared
            .tokenConfiguration(bookId: bookId)
        let priority = QuickTranslationBookEngineConfigStore.shared
            .priorityConfiguration(bookId: bookId)

        // Khoá mang generation của **cả hai** bộ: hai truyện khác nhau đã khác `bookId`, nhưng cùng
        // một truyện sau khi sửa bộ riêng phải là khoá khác. `priority.signature` cũng phải có mặt —
        // đổi thứ tự ưu tiên mà không đổi khoá là cache cũ tiếp tục trả kết quả của thứ tự cũ.
        let key = "\(globalSnapshot?.generation ?? 0)|\(bookSnapshot?.generation ?? 0)"
            + "|\(tokenConfiguration.signature)|\(priority.signature)|\(bookId ?? "global")|\(text.md5())" as NSString
        if let cached = cache.object(forKey: key) { return cached.result }

        let result = execute(
            text,
            bookSnapshot: bookSnapshot,
            globalSnapshot: globalSnapshot,
            bookId: bookId,
            tokenConfiguration: tokenConfiguration,
            priority: priority
        )
        cache.setObject(CacheEntry(result), forKey: key)
        return result
    }

    public static func clearCache() {
        cache.removeAllObjects()
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
        let matcher = QuickTranslationRuleMatcher(
            text: text,
            dictionaries: QuickTranslationDictionaryToken.resolve(bookId: bookId)
        )
        let disable = QuickTranslationRuleDisableStore.shared.snapshot(bookId: bookId)

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
            includesDisabled: false
        )
        found += collectFound(
            text: text,
            snapshot: globalSnapshot,
            scopeRank: 1,
            matcher: matcher,
            tokenConfiguration: tokenConfiguration,
            disable: disable,
            includesDisabled: false
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
        notesComplexRules: Bool = true,
        onTooComplex: ((Int, Int) -> Void)? = nil
    ) -> [Found] {
        guard let snapshot, !snapshot.rules.isEmpty else { return [] }
        let units = Array(text.utf16)
        let candidates = snapshot.literalIndex.candidates(in: units)
        guard !candidates.isEmpty else { return [] }

        var found: [Found] = []
        for candidate in candidates {
            let rule = snapshot.rules[candidate.ruleIndex]
            if !includesDisabled {
                guard rule.isEnabled(for: tokenConfiguration) else { continue }
                guard !disable.isDisabled(pattern: rule.pattern, scopeRank: scopeRank) else { continue }
            }
            var cursor = 0
            for start in candidate.starts where start >= cursor {
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
                cursor = match.start + max(1, match.length)
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

        for match in selected {
            appendPassthrough(upTo: match.start)
            var rendered = match.rendered
            // Hai rule khớp **liền kề** nhau (không còn ký tự gốc ở giữa) thì hai bản dịch bị dán vào
            // nhau: `十年` + `第一魂技` ra `10 nămHồn kỹ thứ 1`. Tokenizer VietPhrase coi cả cụm Latin
            // là **một** token nên chỗ dán này sống tới output cuối. Chèn một khoảng trắng khi hai đầu
            // đều là chữ/số, và tính nó vào `outputRange` của đoạn này để mảng segment vẫn phủ liền
            // mạch toàn bộ output — span dịch được dựng từ đó.
            if needsSeparator(between: output, and: rendered) {
                rendered = " " + rendered
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

    /// Có cần chèn khoảng trắng giữa phần đã ghép và bản dịch kế tiếp.
    ///
    /// Chỉ chèn khi **cả hai** đầu là chữ hoặc số: gạch nối, dấu câu và khoảng trắng đã tự ngăn cách,
    /// và chữ Hán ở phần gốc thì tokenizer sẽ tự tách nên không cần thêm.
    private static func needsSeparator(between output: String, and rendered: String) -> Bool {
        guard let last = output.unicodeScalars.last, let first = rendered.unicodeScalars.first else {
            return false
        }
        return isWordScalar(last) && isWordScalar(first)
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        // Chữ Hán không tính là "chữ" ở đây: nó thuộc phần gốc chưa dịch và tokenizer tự tách.
        if (0x4E00...0x9FFF).contains(scalar.value) { return false }
        return CharacterSet.alphanumerics.contains(scalar)
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
