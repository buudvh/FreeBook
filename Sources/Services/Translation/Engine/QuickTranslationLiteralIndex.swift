import Foundation

/// Prefilter theo literal bắt buộc — **điều kiện khả thi, không phải tối ưu**.
///
/// Không có nó thì mỗi dòng chương phải thử toàn bộ rule (1.175 rule × ~200 dòng/chương ≈ 235.000
/// lượt scan; với bộ 17.278 rule thì vô phương). Chỉ số này lọc theo hai mức:
/// 1. rule nào có thể khớp — literal bắt buộc phải xuất hiện trong input;
/// 2. rule đó có thể bắt đầu ở **những** vị trí nào — suy từ vị trí literal trừ bề rộng phần đứng trước.
///
/// Không bỏ sót: `requiredLiteral` là điều kiện *cần* của mọi match (literal liên tục dài nhất nằm
/// ngoài mọi token và mọi group), nên loại rule khi literal vắng mặt là an toàn.
public struct QuickTranslationLiteralIndex: Sendable {
    public struct Candidate: Sendable {
        public let ruleIndex: Int
        /// Vị trí bắt đầu (UTF-16) cần thử, tăng dần, không trùng.
        public let starts: [Int]
    }

    private struct Entry {
        let ruleIndex: Int
        let literal: [UInt16]
        let prefixMin: Int
        let prefixMax: Int
    }

    /// Gom theo **đơn vị UTF-16 đầu tiên** của literal rồi xác nhận toàn bộ literal tại chỗ.
    private let buckets: [UInt16: [Entry]]
    /// Rule không chứng minh được literal bắt buộc nào ⇒ phải thử mọi vị trí.
    private let alwaysTry: [Int]

    public init(rules: [QuickTranslationCompiledRule]) {
        var buckets: [UInt16: [Entry]] = [:]
        var alwaysTry: [Int] = []

        for (index, rule) in rules.enumerated() {
            guard let first = rule.requiredLiteral.first else {
                alwaysTry.append(index)
                continue
            }
            buckets[first, default: []].append(Entry(
                ruleIndex: index,
                literal: rule.requiredLiteral,
                prefixMin: rule.requiredLiteralPrefixMin,
                prefixMax: rule.requiredLiteralPrefixMax
            ))
        }

        self.buckets = buckets
        self.alwaysTry = alwaysTry
    }

    public var alwaysTryCount: Int { alwaysTry.count }

    public func candidates(in units: [UInt16]) -> [Candidate] {
        guard !units.isEmpty else { return [] }
        var startsByRule: [Int: [Int]] = [:]

        for position in units.indices {
            guard let bucket = buckets[units[position]] else { continue }
            for entry in bucket {
                guard matches(entry.literal, in: units, at: position) else { continue }
                let highest = position - entry.prefixMin
                guard highest >= 0 else { continue }
                let lowest = max(0, position - entry.prefixMax)
                guard lowest <= highest else { continue }
                startsByRule[entry.ruleIndex, default: []].append(contentsOf: lowest...highest)
            }
        }

        var result: [Candidate] = []
        result.reserveCapacity(startsByRule.count + alwaysTry.count)

        for (ruleIndex, starts) in startsByRule {
            var unique: [Int] = []
            for start in starts.sorted() where unique.last != start {
                unique.append(start)
            }
            result.append(Candidate(ruleIndex: ruleIndex, starts: unique))
        }

        if !alwaysTry.isEmpty {
            let everyStart = Array(units.indices)
            for ruleIndex in alwaysTry {
                result.append(Candidate(ruleIndex: ruleIndex, starts: everyStart))
            }
        }

        return result
    }

    private func matches(_ literal: [UInt16], in units: [UInt16], at position: Int) -> Bool {
        guard position + literal.count <= units.count else { return false }
        for offset in literal.indices where units[position + offset] != literal[offset] {
            return false
        }
        return true
    }
}
