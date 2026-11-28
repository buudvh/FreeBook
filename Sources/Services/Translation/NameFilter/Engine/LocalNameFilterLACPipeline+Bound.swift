import Foundation

/// Đợt 4 (2026-11-28) của phía LAC — `extend_right` / `extend_left` / `INFERRED_TITLES` của `lacpipe.py` (khối "Đợt 4"; đo
/// trên file anh Bửu xuất từ màn duyệt + 11 truyện): LAC hay **cắt cụt** thực thể. Một cụm sắp thành hàng (chưa có trong từ
/// điển, toàn chữ Hán dải bộ luật, không nằm trong "Không phải name") mà **một** chữ Hán đứng ngay cạnh nó ở ≥ 90 % số lần
/// xuất hiện (cụm ≥ 3 lần) thì chữ đó thuộc về cụm ⇒ nối vào, tối đa 3 chữ mỗi phía.
///
/// **Nối phải** — chỉ thực thể Nhân danh (địa danh hay có danh từ chung đứng sau: 古墟河|空域): 寒尸冥 → 寒尸冥将, 赤瑶 → 赤瑶蚊.
/// - Bỏ cả cụm (`bound_glued`) khi nối đủ chuỗi dính thì lộ ra một tên người mở đầu bằng họ **vắt qua chỗ nối**
///   (天机阁主|姬长发), hoặc chữ dính là hư từ mà cặp "chữ cuối + hư từ" không có trong từ điển và không phải danh xưng suy
///   ra (宝剑锋|从, 艺多|不).
/// - Dừng nối (cụm đã trọn) khi chữ dính là họ (五鬼老三|范… — biệt hiệu + tên), khi ≥ 1/3 số lần dính là một hậu tố ≥ 2 chữ
///   của danh sách bắt đầu ngay sau (穷朔|洞主), hoặc chữ dính + chữ dính kế là một từ của từ điển (无餍|真身, 觉罡|上人).
/// - **Danh xưng suy ra**: cặp "chữ cuối + chữ dính" lặp ở ≥ 3 thực thể Nhân danh chưa có (寒尸冥|将, 沉夜冥|将, 葬戈冥|将 ⇒
///   冥将) ⇒ nối dù chữ dính là hư từ.
///
/// **Nối trái** — mọi nhóm: 情谷 → 问情谷, 波特王国 → 费内波特王国.
/// - Bỏ cả cụm khi trong chuỗi dính có thực thể **vắt qua chỗ nối** (bắt đầu ở phần nối, kết thúc trong cụm) mà phần còn
///   lại không phải hậu tố — hai cụm dính nhau (熊妖|撼山妖尊, 镇北侯|潘凤); có một thực thể như vậy để lại đúng một hậu tố thì
///   là tên + hậu tố (考伊姆|公司), không bỏ.
/// - Dừng nối khi chữ dính là hư từ / chữ thân tộc, khi ≥ 1/3 số lần dính là một danh xưng ≥ 2 chữ của danh sách kết thúc
///   ngay trước (老怪|卞琦), hoặc chữ dính kế + chữ dính là một từ của từ điển (魁首|厉辉).
///
/// "Thực thể" = name đã có, hoặc từ LAC gắn nhãn thực thể đủ "Ít nhất N lần" (đếm thô). Người gọi
/// (`LocalNameFilterLACPipeline.run`) xét tiếp cụm đã nối: đã là thực thể khác ⇒ `bound_merged`; từ thường ⇒
/// `dict_common_word`; dính thực thể mạnh ⇒ `glued_fragment`.
extension LocalNameFilterLACPipeline {
    private typealias Hit = (unit: UInt16, count: Int)

    /// `INFERRED_TITLES`: cặp 2 chữ. `nil` ⇒ task bị huỷ giữa chừng.
    func inferredTitles(_ merged: [Word: Tally]) -> Set<Word>? {
        var heads: [Word: Int] = [:]
        for (index, (word, tally)) in merged.enumerated() {
            if index & 255 == 0, Task.isCancelled { return nil }
            guard Int(tally.total) >= setup.minCount, word.count >= 2, tally.dominant == .person,
                  let units = word.ruleHanUnits, dictionaries.status(word: word) == nil,
                  let hit = boundUnit(units, right: true) else { continue }
            heads[Self.word([units[units.count - 1], hit.unit]), default: 0] += 1
        }
        var titles = Set<Word>()
        for (pair, count) in heads where count >= Rules.inferredTitleMinHeads { titles.insert(pair) }
        return titles
    }

    /// Cụm sau khi nối (chính `word` khi không nối); `nil` ⇒ bỏ (`bound_glued`). `tag` = nhãn LAC nhiều nhất của cụm.
    func boundTarget(_ word: Word, tag: LocalNameFilter.Category, inferred: Set<Word>) -> Word? {
        guard word.count >= 2, !setup.blockedWords.contains(word), var units = word.ruleHanUnits else { return word }
        if tag == .person {
            guard let extended = extendedRight(units, inferred: inferred) else { return nil }
            units = extended
        }
        guard let extended = extendedLeft(units) else { return nil }
        return extended.count == word.count ? word : Self.word(extended)
    }

    /// `is_rule_han(w) and bound_char(w, "right")` — cụm (toàn chữ Hán dải bộ luật) dính một chữ ngay sau ≥ 90 % số lần. Đợt 5
    /// (GL): "thực thể + một chữ đuôi" chỉ được giữ khi cụm không dính như vậy (临济城镇|魔司).
    func isBoundRight(_ word: Word) -> Bool {
        guard let units = word.ruleHanUnits else { return false }
        return boundUnit(units, right: true) != nil
    }

    // MARK: - Nối

    /// `extend_right(w)`.
    private func extendedRight(_ units: [UInt16], inferred: Set<Word>) -> [UInt16]? {
        let chain = boundChain(units, right: true)
        guard !chain.isEmpty else { return units }
        let full = units + chain.map { $0.unit }
        for start in 1..<units.count where setup.has(full[start], .surnameSingle) {
            for end in (units.count + 1)...full.count where isEntity(Self.word(full[start..<end])) { return nil }
        }
        var current = units
        for (index, hit) in chain.enumerated() {
            let pair = Self.word([current[current.count - 1], hit.unit])
            let isInferred = inferred.contains(pair)
            if Rules.has(hit.unit, .lacFunction), !isInferred, dictionaries.status(word: pair) == nil { return nil }
            if setup.has(hit.unit, .surnameSingle) { break }
            if listedCount(after: current, first: hit.unit) >= Rules.boundListedRatio * Double(hit.count) { break }
            if !isInferred, index + 1 < chain.count,
               dictionaries.status(word: Self.word([hit.unit, chain[index + 1].unit])) != nil {
                break
            }
            current.append(hit.unit)
        }
        return current
    }

    /// `extend_left(w)`.
    private func extendedLeft(_ units: [UInt16]) -> [UInt16]? {
        let chain = boundChain(units, right: false)
        guard !chain.isEmpty else { return units }
        let added = chain.count
        let full = chain.reversed().map { $0.unit } + units
        var good = false
        var bad = false
        for start in 0..<added {
            for end in (added + 1)..<full.count where isEntity(Self.word(full[start..<end])) {
                let rest = Self.word(full[end...])
                if setup.isGlueKeep(rest) || (rest.count == 1 && setup.lacSuffixChars.contains(rest[0])) {
                    good = true
                } else {
                    bad = true
                }
            }
        }
        if bad, !good { return nil }
        var current = units
        for (index, hit) in chain.enumerated() {
            if Rules.has(hit.unit, .function) || Rules.has(hit.unit, .kinship) { break }
            if titledCount(before: current, last: hit.unit) >= Rules.boundListedRatio * Double(hit.count) { break }
            if index + 1 < chain.count,
               dictionaries.status(word: Self.word([chain[index + 1].unit, hit.unit])) != nil {
                break
            }
            current.insert(hit.unit, at: 0)
        }
        return current
    }

    // MARK: - Tra

    /// `bound_char(w, side)`: chữ đứng ngay sau / trước ≥ 90 % số lần (nhiều nhất một chữ đạt ngưỡng).
    private func boundUnit(_ units: [UInt16], right: Bool) -> Hit? {
        let found = counter.neighbors(units: units)
        guard found.count >= Rules.boundMinCount else { return nil }
        let threshold = Rules.boundRatio * Double(found.count)
        let table = right ? found.right : found.left
        for (unit, count) in table where Double(count) >= threshold {
            return (unit: unit, count: count)
        }
        return nil
    }

    /// `bound_chain(w, side)`: các chữ dính liên tiếp (gần cụm trước), tối đa `boundMaxSteps`.
    private func boundChain(_ units: [UInt16], right: Bool) -> [Hit] {
        var chain: [Hit] = []
        var current = units
        for _ in 0..<Rules.boundMaxSteps {
            guard let hit = boundUnit(current, right: right) else { break }
            chain.append(hit)
            if right {
                current.append(hit.unit)
            } else {
                current.insert(hit.unit, at: 0)
            }
        }
        return chain
    }

    /// `is_entity(e)`.
    private func isEntity(_ word: Word) -> Bool {
        guard word.count >= 2 else { return false }
        if dictionaries.status(word: word) == .known { return true }
        return Int(counts.entities[word]?.tally.total ?? 0) >= setup.minCount
    }

    /// `sum(text_count(cur + s) for s in SUFFIX_BY_FIRST[ch])`.
    private func listedCount(after units: [UInt16], first: UInt16) -> Double {
        var total = 0
        for suffix in setup.suffixesByFirst[UInt32(first)] ?? [] {
            guard let tail = suffix.ruleHanUnits else { continue }
            total += counter.count(units: units + tail)
        }
        return Double(total)
    }

    /// `sum(text_count(s + cur) for s in TITLE_BY_LAST[ch])`.
    private func titledCount(before units: [UInt16], last: UInt16) -> Double {
        var total = 0
        for title in setup.personTitlesByLast[UInt32(last)] ?? [] {
            guard let head = title.ruleHanUnits else { continue }
            total += counter.count(units: head + units)
        }
        return Double(total)
    }

    private static func word<S: Sequence>(_ units: S) -> Word where S.Element == UInt16 {
        Word(scalars: units.map { UInt32($0) })
    }
}
