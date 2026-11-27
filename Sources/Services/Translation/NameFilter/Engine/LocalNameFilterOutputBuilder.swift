import Foundation

/// Bước cuối của một lần chụp ⇒ `LocalNameFilter.Snapshot`.
///
/// - Có model LAC (`withLAC`): hàng phía LAC + **bước hợp** của `lacpipe.py` — thêm hàng bộ luật (v3) chưa có, không phải
///   mảnh, không phải name đã có: địa danh / tổ chức / họ tộc (LAC hay sót 极星岛, 海神家族); tên người chỉ khi LAC từng gắn
///   PER cho đúng cụm đó (đếm thô, trước khi gộp).
/// - Đường lùi "chỉ bộ luật" (`rulesOnly`): hàng bộ luật (v2), kể cả name đã có.
///
/// Rồi lọc "Không phải name" (`user_blocked`) và "Loại cần tìm" (`category_off`) — cả danh sách hiện dần — và sắp theo số
/// lần giảm dần, rồi chữ Hán theo code point (`(−count, term)` của bản Python).
struct LocalNameFilterOutputBuilder {
    private typealias Reason = LocalNameFilterRules.Reason

    /// Một hàng bộ luật đã qua luật (hoặc là name đã có) — `LocalNameFilterEngine.decide` trả.
    struct RuleRow {
        let term: LocalNameFilterTermKey
        let name: LocalNameFilter.Name
        let isKnown: Bool
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
        titles: Set<LocalNameFilterTermKey>,
        chaptersRead: Int
    ) -> Result {
        var items: [Item] = []
        items.reserveCapacity(lac.rows.count + ruleRows.count / 4)
        for row in lac.rows {
            let built = meanings.meaning(word: row.word, kind: row.kind, suffix: row.suffix, titles: titles)
            items.append(Item(word: row.word, name: LocalNameFilter.Name(
                term: row.word.string,
                meaning: built.meaning,
                kind: row.kind,
                count: row.count,
                chapterCount: row.chapterCount,
                title: built.title?.string
            ), isKnown: row.isKnown))
        }
        let have = Set(lac.rows.map(\.word))
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
            items.append(Item(word: word, name: row.name, isKnown: false))
            added += 1
        }
        return Result(snapshot: finish(items, reasons: lac.reasons, chaptersRead: chaptersRead), unionAdded: added)
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
}
