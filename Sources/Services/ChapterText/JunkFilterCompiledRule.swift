import Foundation

/// Một quy tắc lọc rác đang bật, đã biên dịch: regex (nil với chuỗi thường) + điều kiện cần để nó có thể khớp
/// (`JunkFilterTextProbe.mayMatch`). Dựng một lần mỗi khi bộ quy tắc đổi (`JunkFilterManager.updateCache`, và bản đã
/// chuyển phồn → giản), không dựng lại theo chương.
struct JunkFilterCompiledRule {
    let rule: JunkFilterRule
    let regex: NSRegularExpression?
    /// Đơn vị UTF-16 phải có mặt trong chữ (gốc ∪ NFD). Rỗng cùng `requiredPairSlots` rỗng ⇒ luôn chạy.
    let requiredUnits: [UInt16]
    /// Ô băm (`JunkFilterTextProbe.pairSlot`) của cặp starter liền nhau phải có trong NFD của chữ.
    let requiredPairSlots: [Int]

    /// `nil` ⇔ regex không biên dịch được — bỏ quy tắc, như `try?` trước đây.
    static func compile(_ rule: JunkFilterRule) -> JunkFilterCompiledRule? {
        guard rule.isRegex else {
            let requirement = literalRequirement(for: rule.pattern)
            return JunkFilterCompiledRule(
                rule: rule, regex: nil, requiredUnits: requirement.units, requiredPairSlots: requirement.pairSlots
            )
        }
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) else { return nil }
        var units: [UInt16] = []
        var seen = Set<UInt16>()
        for scalar in JunkFilterRegexLiterals.requiredScalars(in: rule.pattern) {
            for unit in String(Character(scalar)).utf16 where seen.insert(unit).inserted {
                units.append(unit)
            }
        }
        return JunkFilterCompiledRule(rule: rule, regex: regex, requiredUnits: units, requiredPairSlots: [])
    }

    /// Mẫu chuỗi thường (`replaceOccurrences`, options `[]` ⇒ khớp theo tương đương chính tắc): mọi đơn vị của NFD(mẫu),
    /// và cặp starter liền nhau trong NFD(mẫu) (cặp có ký tự ngoài BMP thì bỏ, chỉ giữ điều kiện đơn vị).
    private static func literalRequirement(for pattern: String) -> (units: [UInt16], pairSlots: [Int]) {
        let decomposed = (pattern as NSString).decomposedStringWithCanonicalMapping
        var units: [UInt16] = []
        var seenUnits = Set<UInt16>()
        for unit in decomposed.utf16 where seenUnits.insert(unit).inserted {
            units.append(unit)
        }
        var slots: [Int] = []
        // Đơn vị surrogate (kể cả lẻ cặp) ⇒ `unicodeScalars` có thể ra U+FFFD khác đơn vị thật trong chữ ⇒ không dùng cặp.
        guard !units.contains(where: { (0xD800...0xDFFF).contains($0) }) else { return (units, slots) }
        var seenSlots = Set<Int>()
        var previousStarter: UInt16?
        for scalar in decomposed.unicodeScalars {
            let isStarter = scalar.properties.canonicalCombiningClass.rawValue == 0
            guard isStarter, scalar.value <= 0xFFFF else {
                previousStarter = nil
                continue
            }
            let unit = UInt16(scalar.value)
            if let previousStarter {
                let slot = JunkFilterTextProbe.pairSlot(previousStarter, unit)
                if seenSlots.insert(slot).inserted { slots.append(slot) }
            }
            previousStarter = unit
        }
        return (units, slots)
    }
}
