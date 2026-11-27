import Foundation

/// `check(s, t, kind, extra, c)` của bản thử Python — xét **một** cách hiểu `(kind, extra)` của một ứng viên, đúng thứ tự
/// luật; trả tên luật bỏ (đúng chuỗi Python, `LocalNameFilterRules.Reason`) hoặc `nil` = qua.
///
/// `c` là số lần xuất hiện thật (`occ`, lượt 2). Mọi ngưỡng so bằng số thực như Python (`n >= 0.6 * c`…).
struct LocalNameFilterRuleChecker {
    typealias Term = LocalNameFilterTermKey
    private typealias Reason = LocalNameFilterRules.Reason

    let setup: LocalNameFilterSetup
    let dictionaries: LocalNameFilterDictionaries
    let occurrences: LocalNameFilterOccurrences
    let counter: LocalNameFilterTextCounter

    func check(_ index: Int, term: Term, kind: LocalNameFilter.Kind, extra: Int, count: Int) -> String? {
        let total = Double(count)
        let isPersonLike = kind == .person || kind == .family
        let isPlaceLike = kind == .place || kind == .sect
        let surnameLength = isPersonLike ? extra : 0
        let units = term.units

        // Hình dạng: tên có hư từ; địa danh mở đầu bằng chữ cấm hoặc có hư từ ở giữa (trước đuôi).
        if isPersonLike {
            if units[surnameLength...].contains(where: { LocalNameFilterRules.has($0, .function) }) {
                return Reason.shapeFunctionChar
            }
        } else if LocalNameFilterRules.has(units[0], .placeBadStart)
                    || units[1..<max(1, term.count - extra)].contains(where: { LocalNameFilterRules.has($0, .function) }) {
            return Reason.shapePlaceStart
        }

        // Danh xưng (TITLE_MODE = "combine"): tên + danh xưng giữ cả cụm; họ + danh xưng mà "họ" thật ra là đuôi môn phái /
        // tên chỗ đứng trước (七宝琉璃宗|宗主) ⇒ mảnh.
        var hasTitle = false
        if kind == .person, !occurrences.titles.isEmpty {
            let tail = setup.pronounTail(of: term, surnameLength: surnameLength)
            if let tail, occurrences.titles.contains(tail) {
                hasTitle = true
                if term.count - tail.count == surnameLength,
                   Double(occurrences.glueSuffix[index]) >= LocalNameFilterRules.glue * total {
                    return Reason.glueLeft
                }
            }
        }

        // Tên / họ + danh xưng (江镖头, 林师兄): danh xưng là từ thường trong VP nhưng cụm vẫn là name — không xét "từ thường".
        if kind == .person, !hasTitle {
            if term.count >= 3, commonPart(term.slice(0, 2), total: total) { return Reason.dictCommonHead }
            if let given = term.dropFirst(surnameLength), given.count == 2, commonPart(given, total: total) {
                return Reason.dictCommonGiven
            }
        }
        if isPlaceLike, extra == 1 {
            // Chữ áp chót cũng là đuôi (城市, 海域, 宫殿): chỉ bỏ khi phần trước (≥ 2 chữ) cũng là từ thường (STRICT_TAIL) —
            // 海边|城市, 周围|海域 bỏ; 登|州府, 青州|府城, 天魂|海军 giữ.
            let loose = setup.has(term[term.count - 2], .suffixChar)
                && !(term.count >= 4 && status(term.dropLast(2)) == .common)
            if !loose, commonPart(term.suffix(2), total: total) { return Reason.dictCommonTail }
        }
        if Double(occurrences.glueLeft[index]) >= LocalNameFilterRules.glue * total { return Reason.glueLeft }
        if Double(occurrences.glueRight[index]) >= LocalNameFilterRules.glue * total {
            if isPersonLike || status(term.dropLast(extra)) == .known { return Reason.glueRight }
        }
        if isPlaceLike {
            for start in stride(from: 1, to: term.count - extra, by: 1) {
                guard let tail = term.dropFirst(start) else { continue }
                if tail.units.allSatisfy({ setup.has($0, .suffixChar) }) { continue }
                let tailStatus = status(tail)
                if tail.count >= 2,
                   tailStatus == .known || (tailStatus == nil && occurrences.survivorIndex[tail] != nil),
                   Double(counter.count(tail)) >= LocalNameFilterRules.containedRatio * total {
                    return Reason.containedKnownTail
                }
            }
        }
        let rightCounter = kind == .person ? occurrences.rightPerson[index] : occurrences.right[index]
        if dominant(rightCounter, total: total, light: .rightLight) { return Reason.boundRight }
        if dominant(occurrences.left[index], total: total, light: .function) { return Reason.boundLeft }
        return nil
    }

    /// `common_part(part)`: từ thường trong VP và xuất hiện ≥ 1,5 × c lần trong truyện.
    private func commonPart(_ part: Term?, total: Double) -> Bool {
        guard let part, dictionaries.status(part) == .common else { return false }
        return Double(counter.count(part)) >= LocalNameFilterRules.commonPartRatio * total
    }

    private func status(_ term: Term?) -> LocalNameFilterDictionaries.Status? {
        term.flatMap { dictionaries.status($0) }
    }

    /// `dominant(counter, total, light)`: có một chữ (không phải ranh giới `0`) đứng cạnh ≥ 60 % số lần — ≥ 90 % nếu là
    /// chữ "nhẹ" (`light`).
    private func dominant(_ counter: [UInt16: Int32], total: Double, light: LocalNameFilterRules.CharClass) -> Bool {
        for (unit, count) in counter where unit != 0 {
            let ratio = LocalNameFilterRules.has(unit, light) ? LocalNameFilterRules.lightDominance : LocalNameFilterRules.dominance
            if Double(count) >= ratio * total { return true }
        }
        return false
    }
}
