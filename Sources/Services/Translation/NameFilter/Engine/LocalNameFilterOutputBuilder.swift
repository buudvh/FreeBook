import Foundation

/// Bước cuối của một lần chụp ⇒ `LocalNameFilter.Snapshot`.
///
/// - Có model LAC (`withLAC`): hàng phía LAC + **bước hợp** của `lacpipe.py` — thêm hàng bộ luật (v3) chưa có, không phải
///   mảnh, không phải name đã có: địa danh / tổ chức / họ tộc (LAC hay sót 极星岛, 海神家族); tên người chỉ khi LAC từng gắn
///   PER cho đúng cụm đó (đếm thô, trước khi gộp). Hàng bộ luật cũng chịu L5 (`rank_prefix`). Sau khi hợp: L9 — name chưa
///   có ghép đúng hai hàng **Nhân danh** của danh sách, mỗi phần ≥ 2 chữ (姬晴|苟义) ⇒ bỏ (`glued_names`). Plan
///   2026-11-27-phan-loai-name. Rồi luật rác L17–L22 (`junk_reason`, 2026-11-28 — `LocalNameFilterJunkRules`): name chưa có
///   ghép từ hai name (`glued_entities`), giới từ + hậu tố (`prep_head`), chữ lặp / chữ số (`repeat_or_digit`), tên người
///   toàn từ thường (`common_phrase`), động từ + đuôi ở hàng bộ luật (`verb_head`), tên người + 1 chữ hiếm (`name_fragment`);
///   đợt 3 thêm lượng từ số đông đứng đầu (`quantity_head`, L25) và tên bị cắt giữa danh xưng (`title_fragment`, L24).
/// - Đường lùi "chỉ bộ luật" (`rulesOnly`): hàng bộ luật (v2), kể cả name đã có — không có L5 / L9 / L17–L25 (như
///   `fallback_rules.py`).
///
/// Rồi lọc "Không phải name" (`user_blocked`), "Loại cần tìm" (`category_off`) và "Độ dài name" (`length_off`, L15 — đếm
/// code point, không tính `·`) — cả danh sách hiện dần, cả hai đường — và sắp theo số lần giảm dần, rồi chữ Hán theo code
/// point (`(−count, term)` của bản Python).
struct LocalNameFilterOutputBuilder {
    private typealias Reason = LocalNameFilterRules.Reason

    /// Một hàng bộ luật đã qua luật (hoặc là name đã có) — `LocalNameFilterEngine.decide` trả.
    struct RuleRow {
        let term: LocalNameFilterTermKey
        let name: LocalNameFilter.Name
        let isKnown: Bool
        /// Số chữ của đuôi đã dò khi hàng là địa danh / tổ chức (`rule["suffix"]` của Python), `nil` với tên người / họ tộc —
        /// luật rác L18 / L22.
        var suffixLength: Int? = nil
    }

    struct Result {
        let snapshot: LocalNameFilter.Snapshot
        /// Số hàng bộ luật thêm ở bước hợp (0 ở đường lùi).
        let unionAdded: Int
    }

    private struct Item {
        let word: LocalNameFilterWord
        let name: LocalNameFilter.Name
        let isKnown: Bool
        /// Hàng bộ luật thêm ở bước hợp (`"rule" in r`).
        var isRuleRow = false
        /// Hàng bộ luật: `RuleRow.suffixLength`.
        var ruleSuffixLength: Int?

        var junkRow: LocalNameFilterJunkRules.Row {
            LocalNameFilterJunkRules.Row(word: word, category: name.category, count: name.count, isRuleRow: isRuleRow,
                                         ruleSuffixLength: ruleSuffixLength)
        }
    }

    let setup: LocalNameFilterSetup
    let meanings: LocalNameFilterMeaningBuilder

    func rulesOnly(_ rows: [RuleRow], reasons: [String: Int], chaptersRead: Int) -> Result {
        let items = rows.map { Item(word: LocalNameFilterWord($0.term), name: $0.name, isKnown: $0.isKnown) }
        return Result(snapshot: finish(items, reasons: reasons, chaptersRead: chaptersRead), unionAdded: 0)
    }

    func withLAC(
        _ lac: LocalNameFilterLACPipeline.Output,
        ruleRows: [RuleRow],
        counts: LocalNameFilterLACCounts,
        counter: LocalNameFilterTextCounter,
        titles: Set<LocalNameFilterTermKey>,
        chaptersRead: Int
    ) -> Result {
        var items: [Item] = []
        items.reserveCapacity(lac.rows.count + ruleRows.count / 4)
        for row in lac.rows {
            let built = meanings.meaning(word: row.word, kind: row.kind, titles: titles,
                                         dictionaryTitle: row.dictionaryTitle)
            items.append(Item(word: row.word, name: LocalNameFilter.Name(
                term: row.word.string,
                meaning: built.meaning,
                kind: row.kind,
                count: row.count,
                chapterCount: row.chapterCount,
                title: built.title?.string,
                isGuessedMeaning: built.isGuessed
            ), isKnown: row.isKnown))
        }
        let have = Set(lac.rows.map(\.word))
        var reasons = lac.reasons
        var added = 0
        for row in ruleRows where !row.isKnown {
            let word = LocalNameFilterWord(row.term)
            guard !have.contains(word), !lac.fragments.contains(word) else { continue }
            switch row.name.kind {
            case .place, .sect, .family:
                break
            case .person:
                guard (counts.entities[word]?.tally.person ?? 0) >= 1 else { continue }
            case .term:
                continue
            }
            if LocalNameFilterRules.isRankPrefix(word) {
                reasons[Reason.rankPrefix, default: 0] += 1
                continue
            }
            items.append(Item(word: word, name: row.name, isKnown: false, isRuleRow: true,
                              ruleSuffixLength: row.suffixLength))
            added += 1
        }
        items = droppingGluedNames(items, reasons: &reasons)
        items = droppingJunk(items, counts: counts, counter: counter, reasons: &reasons)
        return Result(snapshot: finish(items, reasons: reasons, chaptersRead: chaptersRead), unionAdded: added)
    }

    /// L9 (`glued_names`): name chưa có = đúng hai hàng Nhân danh khác của danh sách (cả hàng đã có), mỗi phần ≥ 2 chữ.
    private func droppingGluedNames(_ items: [Item], reasons: inout [String: Int]) -> [Item] {
        let persons = Set(items.lazy.filter { $0.name.kind == .person }.map(\.word))
        guard persons.count >= 2 else { return items }
        return items.filter { item in
            guard !item.isKnown, item.word.count >= 4 else { return true }
            let word = item.word
            let glued = (2...(word.count - 2)).contains { split in
                persons.contains(word.slice(0, split)) && persons.contains(word.slice(split, word.count))
            }
            if glued { reasons[Reason.gluedNames, default: 0] += 1 }
            return !glued
        }
    }

    /// Luật rác L17–L25 + đợt 4 (`junk_reason` + `title_fragment` + `context_junk`): bảng tra dựng từ mọi hàng sau L9 (kể cả name đã có), chỉ xét name chưa có.
    private func droppingJunk(
        _ items: [Item],
        counts: LocalNameFilterLACCounts,
        counter: LocalNameFilterTextCounter,
        reasons: inout [String: Int]
    ) -> [Item] {
        let rows = items.map(\.junkRow)
        let rules = LocalNameFilterJunkRules(rows: rows, setup: setup, dictionaries: meanings.dictionaries, counts: counts,
                                            counter: counter)
        var kept: [Item] = []
        kept.reserveCapacity(items.count)
        for (item, row) in zip(items, rows) {
            if !item.isKnown, let reason = rules.reason(for: row) {
                reasons[reason, default: 0] += 1
            } else {
                kept.append(item)
            }
        }
        return kept
    }

    private func finish(_ items: [Item], reasons: [String: Int], chaptersRead: Int) -> LocalNameFilter.Snapshot {
        var reasons = reasons
        var kept: [Item] = []
        kept.reserveCapacity(items.count)
        for item in items {
            if setup.blockedWords.contains(item.word) {
                reasons[Reason.userBlocked, default: 0] += 1
            } else if !setup.categories.contains(item.name.category) {
                reasons[Reason.categoryOff, default: 0] += 1
            } else if !fitsLength(item.word) {
                reasons[Reason.lengthOff, default: 0] += 1
            } else {
                kept.append(item)
            }
        }
        kept.sort { lhs, rhs in
            lhs.name.count != rhs.name.count ? lhs.name.count > rhs.name.count : lhs.word < rhs.word
        }
        return LocalNameFilter.Snapshot(
            names: kept.map(\.name),
            knownCount: kept.reduce(0) { $0 + ($1.isKnown ? 1 : 0) },
            droppedByReason: reasons,
            chaptersRead: chaptersRead
        )
    }

    /// "Độ dài name" (L15).
    private func fitsLength(_ word: LocalNameFilterWord) -> Bool {
        let length = LocalNameFilterRules.nameLength(word)
        if length < setup.minLength { return false }
        if let maxLength = setup.maxLength, length > maxLength { return false }
        return true
    }
}
