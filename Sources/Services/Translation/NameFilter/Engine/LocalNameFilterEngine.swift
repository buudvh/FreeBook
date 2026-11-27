import Foundation

/// Bộ lọc name local (luật + hai lượt quét) — bản Swift của `local_name_filter2.py` với `STRICT_TAIL = True`,
/// `GLUE_SUFFIX = True`, `TITLE_MODE = "combine"`. Thuần: không đọc `TranslationManager`, không I/O; nhận bản chụp từ điển
/// (`LocalNameFilterDictionaries`) + cấu hình lúc tạo.
///
/// - `feed(_:)`: lượt 1 của một chương (`Stream.feed`).
/// - `snapshot(chaptersRead:)`: lượt 2 + luật trên **toàn bộ** phần đã đọc (`Stream.snapshot` + `decide`). Không sửa trạng
///   thái lượt 1 ⇒ chụp bao nhiêu lần giữa chừng, lần chụp cuối vẫn y như chạy một lần. `nil` ⇒ task bị huỷ.
///
/// Không an toàn đa luồng: một lượt lọc dùng trên đúng một task.
final class LocalNameFilterEngine {
    typealias Term = LocalNameFilterTermKey
    private typealias Reason = LocalNameFilterRules.Reason

    /// Kết quả một lần chụp + số đo cho log.
    struct Report {
        let snapshot: LocalNameFilter.Snapshot
        let passTwoMs: Int
        let rulesMs: Int
        /// Số danh xưng (`titles`) lúc chụp.
        let titleCount: Int
    }

    private let setup: LocalNameFilterSetup
    private let dictionaries: LocalNameFilterDictionaries
    private let accumulator: LocalNameFilterAccumulator

    init(configuration: LocalNameFilter.Configuration, dictionaries: LocalNameFilterDictionaries) {
        let setup = LocalNameFilterSetup(configuration: configuration, dictionaries: dictionaries)
        self.setup = setup
        self.dictionaries = dictionaries
        accumulator = LocalNameFilterAccumulator(setup: setup)
    }

    /// Có từ điển Đại từ (bước danh xưng chạy được).
    var hasPronouns: Bool { dictionaries.pronounEntries != nil }
    var hanCount: Int { accumulator.hanCount }

    func feed(_ chapterText: String) {
        accumulator.feed(chapterText)
    }

    func snapshot(chaptersRead: Int) -> Report? {
        let passTwoStart = DispatchTime.now().uptimeNanoseconds
        guard let occurrences = LocalNameFilterOccurrences.scan(accumulator, setup: setup, dictionaries: dictionaries) else {
            return nil
        }
        let rulesStart = DispatchTime.now().uptimeNanoseconds
        guard let snapshot = decide(occurrences, chaptersRead: chaptersRead) else { return nil }
        let end = DispatchTime.now().uptimeNanoseconds
        return Report(
            snapshot: snapshot,
            passTwoMs: Int((rulesStart - passTwoStart) / 1_000_000),
            rulesMs: Int((end - rulesStart) / 1_000_000),
            titleCount: occurrences.titles.count
        )
    }

    // MARK: - decide

    /// `decide(s)` của Python: đã có ⇒ ẩn; từ thường ⇒ bỏ; thử từng cách hiểu theo `KIND_ORDER` (cùng loại thì `extra` lớn
    /// trước), lấy cách đầu tiên qua luật; luật gắn lại Nhân vật; "Không phải name" lọc ở **đầu ra**; dựng nghĩa; sắp theo
    /// số lần giảm dần rồi chữ Hán.
    private func decide(_ occurrences: LocalNameFilterOccurrences, chaptersRead: Int) -> LocalNameFilter.Snapshot? {
        let checker = LocalNameFilterRuleChecker(
            setup: setup, dictionaries: dictionaries, occurrences: occurrences,
            counter: LocalNameFilterTextCounter(accumulator: accumulator)
        )
        let meanings = LocalNameFilterMeaningBuilder(setup: setup, dictionaries: dictionaries)
        var reasons: [String: Int] = [:]
        var hiddenKnown = 0
        var kept: [(term: Term, name: LocalNameFilter.Name)] = []

        for (index, term) in occurrences.survivors.enumerated() {
            if index & 255 == 0, Task.isCancelled { return nil }
            let count = Int(occurrences.occurrences[index])
            guard count >= setup.minCount else { continue }
            switch dictionaries.status(term) {
            case .known:
                hiddenKnown += 1
                continue
            case .common:
                reasons[Reason.dictCommonWord, default: 0] += 1
                continue
            case nil:
                break
            }
            guard let stats = accumulator.stats[term] else { continue }

            var passed: [(kind: LocalNameFilter.Kind, extra: Int)] = []
            var firstFailure: String?
            for (order, kind) in LocalNameFilterRules.kindOrder.enumerated() {
                for extra in stride(from: 2, through: 1, by: -1)
                where stats.kinds & LocalNameFilterRules.kindBit(order: order, extra: extra) != 0 {
                    if let reason = checker.check(index, term: term, kind: kind, extra: extra, count: count) {
                        if firstFailure == nil { firstFailure = reason }
                    } else {
                        passed.append((kind, extra))
                    }
                }
            }
            guard var chosen = passed.first else {
                if let firstFailure { reasons[firstFailure, default: 0] += 1 }
                continue
            }
            if chosen.kind != .person, let person = passed.first(where: { $0.kind == .person }),
               shouldPreferPerson(index, term: term, chosenExtra: chosen.extra, occurrences: occurrences) {
                chosen = person
            }

            // Danh sách "Không phải name": lọc ở đầu ra, không đổi số liệu của từ khác.
            if setup.blockedTerms.contains(term) {
                reasons[Reason.userBlocked, default: 0] += 1
                continue
            }
            let built = meanings.meaning(term: term, kind: chosen.kind, extra: chosen.extra, titles: occurrences.titles)
            kept.append((term, LocalNameFilter.Name(
                term: term.string,
                meaning: built.meaning,
                kind: chosen.kind,
                count: count,
                chapterCount: Int(stats.chapters),
                title: built.title?.string
            )))
        }

        kept.sort { lhs, rhs in
            lhs.name.count != rhs.name.count ? lhs.name.count > rhs.name.count : lhs.term < rhs.term
        }
        return LocalNameFilter.Snapshot(
            names: kept.map(\.name),
            hiddenKnownCount: hiddenKnown,
            droppedByReason: reasons,
            chaptersRead: chaptersRead
        )
    }

    /// Luật gắn lại Nhân vật khi cách hiểu đầu tiên là địa danh / tông môn / họ + 家 mà cách hiểu tên người cũng qua: cụm
    /// ≤ 3 chữ kết thúc bằng đuôi "yếu" (山, 河, 堂…) mà không hay đứng sau giới từ chỉ nơi chốn, hoặc hay đứng trước động từ
    /// nói (说道, 笑…) hơn là sau giới từ chỉ nơi chốn.
    private func shouldPreferPerson(
        _ index: Int,
        term: Term,
        chosenExtra: Int,
        occurrences: LocalNameFilterOccurrences
    ) -> Bool {
        var locative = 0
        for (unit, count) in occurrences.left[index] where unit != 0 && LocalNameFilterRules.has(unit, .locative) {
            locative += Int(count)
        }
        let speech = Int(occurrences.speech[index])
        let weak = LocalNameFilterRules.has(term.last, .weakSuffix) && chosenExtra == 1
        return (term.count <= 3 && weak && !(locative >= 3 && locative > speech)) || (speech >= 2 && speech > locative)
    }
}
