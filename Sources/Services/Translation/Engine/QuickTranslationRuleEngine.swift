import Foundation

/// Áp bộ rule dịch lên một chuỗi Trung: chèn **sau** Phồn thể → Giản thể và **trước** tokenize.
///
/// Thứ tự chọn match giữ đúng ngữ nghĩa `executeRules` của reference (index → literalLength →
/// wildcardCapacity → độ dài match → dòng nguồn), chỉ đổi cách sinh candidate: prefilter theo literal
/// bắt buộc rồi AST-walk, thay vì một regex mỗi rule quét cả chuỗi.
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

    private struct Found {
        let start: Int
        let length: Int
        let literalLength: Int
        let wildcardCapacity: Int
        let sourceLine: Int
        let rendered: String
    }

    /// Memo nhỏ: pipeline gọi `rewrite` hai lần cho cùng một chuỗi (một lần để dịch, một lần để dựng
    /// span), không có memo là chạy engine hai lượt.
    private static let cache: NSCache<NSString, CacheEntry> = {
        let cache = NSCache<NSString, CacheEntry>()
        cache.countLimit = 64
        return cache
    }()

    /// `nil` khi công tắc tắt hoặc chưa có rule nào — bên gọi giữ nguyên đường dịch cũ.
    public static func rewrite(_ text: String, bookId: String?) -> QuickTranslationRewriteResult? {
        guard !text.isEmpty else { return nil }
        guard let snapshot = QuickTranslationRuleStore.shared.activeSnapshot else { return nil }
        let tokenConfiguration = QuickTranslationRuleTokenSettings.currentConfiguration()

        let key = "\(snapshot.generation)|\(tokenConfiguration.signature)|\(bookId ?? "global")|\(text.md5())" as NSString
        if let cached = cache.object(forKey: key) { return cached.result }

        let result = execute(
            text,
            snapshot: snapshot,
            bookId: bookId,
            tokenConfiguration: tokenConfiguration
        )
        cache.setObject(CacheEntry(result), forKey: key)
        return result
    }

    public static func clearCache() {
        cache.removeAllObjects()
    }

    /// Dùng cho ô thử nhanh ở màn hình quản lý: luôn bỏ qua công tắc tổng và không dùng memo.
    /// `mode` chỉ quyết định có tôn trọng tám công tắc token hay xem rule với mọi token được bật.
    public static func preview(
        _ text: String,
        bookId: String? = nil,
        mode: PreviewMode = .respectTokenConfiguration
    ) -> QuickTranslationRewriteResult? {
        guard !text.isEmpty, let snapshot = QuickTranslationRuleStore.shared.currentSnapshot,
              !snapshot.rules.isEmpty else { return nil }
        let tokenConfiguration: QuickTranslationRuleTokenSettings.Configuration
        switch mode {
        case .respectTokenConfiguration:
            tokenConfiguration = QuickTranslationRuleTokenSettings.currentConfiguration()
        case .ignoreTokenConfiguration:
            tokenConfiguration = .allEnabled
        }
        return execute(
            text,
            snapshot: snapshot,
            bookId: bookId,
            tokenConfiguration: tokenConfiguration
        )
    }

    // MARK: - Thi hành

    private static func execute(
        _ text: String,
        snapshot: QuickTranslationRuleSnapshot,
        bookId: String?,
        tokenConfiguration: QuickTranslationRuleTokenSettings.Configuration
    ) -> QuickTranslationRewriteResult {
        let nsText = text as NSString
        let units = Array(text.utf16)
        let candidates = snapshot.literalIndex.candidates(in: units)
        guard !candidates.isEmpty else { return passthrough(text, length: nsText.length) }

        let matcher = QuickTranslationRuleMatcher(
            text: text,
            dictionaries: QuickTranslationDictionaryToken.resolve(bookId: bookId)
        )

        var found: [Found] = []
        for candidate in candidates {
            let rule = snapshot.rules[candidate.ruleIndex]
            guard rule.isEnabled(for: tokenConfiguration) else { continue }
            var cursor = 0
            for start in candidate.starts where start >= cursor {
                guard let match = matcher.match(rule, at: start) else {
                    if matcher.didExceedStepCap {
                        QuickTranslationRuleStore.shared.noteComplexRule(sourceLine: rule.sourceLine)
                        break
                    }
                    continue
                }
                found.append(Found(
                    start: match.start,
                    length: match.length,
                    literalLength: rule.literalLength,
                    wildcardCapacity: rule.wildcardCapacity,
                    sourceLine: rule.sourceLine,
                    rendered: rule.render(captures: match.captures)
                ))
                cursor = match.start + max(1, match.length)
            }
        }

        guard !found.isEmpty else { return passthrough(text, length: nsText.length) }
        return assemble(selected: select(from: found), text: text, nsText: nsText)
    }

    /// Sort một lần rồi quét một pass tuyến tính. Reference gọi `matches.filter(...)` trong vòng
    /// `while` (bậc hai) nhưng kết quả giống hệt.
    private static func select(from found: [Found]) -> [Found] {
        let sorted = found.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.literalLength != rhs.literalLength { return lhs.literalLength > rhs.literalLength }
            if lhs.wildcardCapacity != rhs.wildcardCapacity { return lhs.wildcardCapacity < rhs.wildcardCapacity }
            if lhs.length != rhs.length { return lhs.length > rhs.length }
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
            let rendered = match.rendered
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
