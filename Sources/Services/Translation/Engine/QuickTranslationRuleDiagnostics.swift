import Foundation

/// Soi **một đoạn văn** và trả về mọi lần khớp rule, kèm trạng thái: rule thắng, rule thua chồng lấn,
/// rule đang tắt (riêng/chung), rule bị token tắt, rule chạm cap backtracking.
///
/// Không dùng lại `QuickTranslationRewriteResult` vì bản đồ đoạn của nó chỉ giữ rule **thắng**.
/// Ngược lại, ở đây **bắt buộc** dùng lại `QuickTranslationRuleEngine.collectFound` và
/// `QuickTranslationRuleEngine.select` — cài lại 6 tiêu chí ưu tiên ở chỗ thứ hai là mở đường cho
/// màn chẩn đoán nói khác kết quả dịch thật.
///
/// Chẩn đoán **không được ghi trạng thái**: `notesComplexRules: false` để không bơm
/// `RULE_TOO_COMPLEX` vào `QuickTranslationRuleStore.status` chỉ vì người dùng mở màn xem.
public enum QuickTranslationRuleDiagnostics {

    /// `selection` là vùng người dùng đang bôi đen, tính trên **chính** `text` (đoạn gốc).
    public static func diagnose(
        text: String,
        bookId: String?,
        selection: NSRange? = nil
    ) -> [QuickTranslationRuleTrace] {
        guard !text.isEmpty else { return [] }

        let globalSnapshot = QuickTranslationRuleStore.shared.currentSnapshot
        let bookSnapshot = QuickTranslationRuleBookStore.shared.snapshot(for: bookId)
        guard globalSnapshot != nil || bookSnapshot != nil else { return [] }

        let nsText = text as NSString
        // Cùng bản chụp cấu hình mà bản dịch thật đang dùng — kể cả phần đặt riêng của truyện.
        let tokenConfiguration = QuickTranslationBookEngineConfigStore.shared
            .tokenConfiguration(bookId: bookId)
        let priority = QuickTranslationBookEngineConfigStore.shared
            .priorityConfiguration(bookId: bookId)
        let disable = QuickTranslationRuleDisableStore.shared.snapshot(bookId: bookId)
        let matcher = QuickTranslationRuleMatcher(
            text: text,
            dictionaries: QuickTranslationDictionaryToken.resolve(bookId: bookId)
        )

        var complexBook: [(ruleIndex: Int, start: Int)] = []
        var complexGlobal: [(ruleIndex: Int, start: Int)] = []

        var found = QuickTranslationRuleEngine.collectFound(
            text: text,
            snapshot: bookSnapshot,
            scopeRank: 0,
            matcher: matcher,
            tokenConfiguration: tokenConfiguration,
            disable: disable,
            includesDisabled: true,
            notesComplexRules: false,
            onTooComplex: { index, start in complexBook.append((index, start)) }
        )
        found += QuickTranslationRuleEngine.collectFound(
            text: text,
            snapshot: globalSnapshot,
            scopeRank: 1,
            matcher: matcher,
            tokenConfiguration: tokenConfiguration,
            disable: disable,
            includesDisabled: true,
            notesComplexRules: false,
            onTooComplex: { index, start in complexGlobal.append((index, start)) }
        )

        func snapshotForRank(_ rank: Int) -> QuickTranslationRuleSnapshot? {
            rank == 0 ? bookSnapshot : globalSnapshot
        }

        func scopeForRank(_ rank: Int) -> QuickTranslationRuleScope {
            guard rank == 0, let bookId, !bookId.isEmpty else { return .global }
            return .book(bookId)
        }

        // Rule đủ điều kiện chạy ⇒ mới được dự tranh chấp. Đúng tập mà engine dùng khi dịch thật.
        let eligible = found.filter { item in
            guard let snapshot = snapshotForRank(item.scopeRank),
                  snapshot.rules.indices.contains(item.ruleIndex) else { return false }
            let rule = snapshot.rules[item.ruleIndex]
            guard rule.isEnabled(for: tokenConfiguration) else { return false }
            return !disable.isDisabled(pattern: rule.pattern, scopeRank: item.scopeRank)
        }
        let winners = QuickTranslationRuleEngine.select(from: eligible, priority: priority)
        let winnerKeys = Set(winners.map { "\($0.scopeRank)#\($0.sourceLine)#\($0.start)" })

        var traces: [QuickTranslationRuleTrace] = []

        for item in found {
            guard let snapshot = snapshotForRank(item.scopeRank),
                  snapshot.rules.indices.contains(item.ruleIndex) else { continue }
            let rule = snapshot.rules[item.ruleIndex]
            let key = "\(item.scopeRank)#\(item.sourceLine)#\(item.start)"
            let range = NSRange(location: item.start, length: item.length)

            let status: QuickTranslationRuleTrace.Status
            if winnerKeys.contains(key) {
                status = .applied
            } else if !rule.isEnabled(for: tokenConfiguration) {
                status = .tokenDisabled
            } else if disable.book.contains(rule.pattern) {
                status = .disabledForBook
            } else if item.scopeRank != 0, disable.global.contains(rule.pattern) {
                status = .disabledGlobally
            } else {
                let blocking = winners.first { NSIntersectionRange(
                    NSRange(location: $0.start, length: max(1, $0.length)),
                    NSRange(location: item.start, length: max(1, item.length))
                ).length > 0 }
                status = .lostOverlap(toSourceLine: blocking?.sourceLine ?? rule.sourceLine)
            }

            traces.append(makeTrace(
                rule: rule,
                scope: scopeForRank(item.scopeRank),
                range: range,
                nsText: nsText,
                rendered: item.rendered,
                captures: item.captures,
                status: status,
                selection: selection
            ))
        }

        // Rule chạm cap backtracking không sinh match nào nên không có cụm để tô: range dài 0, UI hiện
        // chip cảnh báo "rule quá phức tạp" mà không tô gì trên thanh gốc.
        for (rank, items) in [(0, complexBook), (1, complexGlobal)] {
            guard let snapshot = snapshotForRank(rank) else { continue }
            var seen = Set<Int>()
            for item in items where snapshot.rules.indices.contains(item.ruleIndex) {
                guard seen.insert(item.ruleIndex).inserted else { continue }
                let rule = snapshot.rules[item.ruleIndex]
                traces.append(makeTrace(
                    rule: rule,
                    scope: scopeForRank(rank),
                    range: NSRange(location: item.start, length: 0),
                    nsText: nsText,
                    rendered: "",
                    captures: [],
                    status: .tooComplex,
                    selection: selection
                ))
            }
        }

        return sorted(traces)
    }

    // MARK: - Sắp xếp

    /// Thắng → tranh chấp → đang tắt / token tắt / quá phức tạp. Trong mỗi nhóm: cụm chạm vùng bôi
    /// đen lên trước, rồi theo vị trí xuất hiện, rồi theo số dòng để thứ tự luôn xác định.
    private static func sorted(_ traces: [QuickTranslationRuleTrace]) -> [QuickTranslationRuleTrace] {
        traces.sorted { lhs, rhs in
            let lhsGroup = group(of: lhs.status)
            let rhsGroup = group(of: rhs.status)
            if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }
            if lhs.isTouchingSelection != rhs.isTouchingSelection { return lhs.isTouchingSelection }
            if lhs.sourceRange.location != rhs.sourceRange.location {
                return lhs.sourceRange.location < rhs.sourceRange.location
            }
            return lhs.sourceLine < rhs.sourceLine
        }
    }

    private static func group(of status: QuickTranslationRuleTrace.Status) -> Int {
        switch status {
        case .applied: return 0
        case .lostOverlap: return 1
        case .disabledForBook, .disabledGlobally, .tokenDisabled: return 2
        case .tooComplex: return 3
        }
    }

    // MARK: - Dựng trace

    private static func makeTrace(
        rule: QuickTranslationCompiledRule,
        scope: QuickTranslationRuleScope,
        range: NSRange,
        nsText: NSString,
        rendered: String,
        captures: [QuickTranslationRuleMatcher.Capture],
        status: QuickTranslationRuleTrace.Status,
        selection: NSRange?
    ) -> QuickTranslationRuleTrace {
        let matchedText: String = {
            guard range.length > 0, NSMaxRange(range) <= nsText.length else { return "" }
            return nsText.substring(with: range)
        }()

        let traceCaptures: [QuickTranslationRuleTrace.Capture] = captures.enumerated().map { index, capture in
            let sourceText: String = {
                guard let captureRange = capture.sourceRange,
                      captureRange.length > 0,
                      NSMaxRange(captureRange) <= nsText.length else { return "" }
                return nsText.substring(with: captureRange)
            }()
            return QuickTranslationRuleTrace.Capture(
                index: index,
                sourceText: sourceText,
                renderedText: capture.text,
                sourceRange: capture.sourceRange
            )
        }

        let touching: Bool = {
            guard let selection, selection.length > 0, range.length > 0 else { return false }
            return NSIntersectionRange(selection, range).length > 0
        }()

        return QuickTranslationRuleTrace(
            scope: scope,
            pattern: rule.pattern,
            replacement: rule.replacement,
            sourceLine: rule.sourceLine,
            sourceRange: range,
            matchedText: matchedText,
            rendered: rendered,
            captures: traceCaptures,
            status: status,
            isTouchingSelection: touching
        )
    }
}
