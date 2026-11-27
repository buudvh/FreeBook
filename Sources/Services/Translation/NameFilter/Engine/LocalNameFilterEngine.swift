import Foundation

/// Bộ lọc name local — bản Swift của `lacpipe.py` + `local_name_filter2.py` (`Docs/Plans/local-name-filter-lac/`). Thuần:
/// không đọc `TranslationManager`, không I/O; nhận bản chụp từ điển (`LocalNameFilterDictionaries`) + cấu hình lúc tạo.
///
/// Hai chế độ, chọn lúc tạo:
/// - **có model LAC** (`usesLAC`): bộ luật chạy với cờ `V3` chỉ để góp hàng ở bước hợp; danh sách chính là phía LAC
///   (`LocalNameFilterLACPipeline`).
/// - **đường lùi "chỉ bộ luật"** (model tự kiểm lệch): bộ luật v2 như trước bản LAC.
/// Cả hai: name đã có **không ẩn** (giữ, đếm `knownCount`), "Không phải name" + "Loại cần tìm" + "Độ dài name" lọc ở đầu
/// ra. Nghĩa đề xuất theo từ điển (+ mô hình đoán tên Latin khi bật "Ưu tiên tên Latin", + tiền tố của danh sách "Tiền tố")
/// — `LocalNameFilterMeaningBuilder`; phần tên riêng nhớ qua mọi lần chụp ở `LocalNameFilterProperNames`. Danh xưng lấy từ
/// hậu tố Nhân danh của danh sách "Hậu tố" (không còn đọc Pronouns — plan 2026-11-27-phan-loai-name L11).
///
/// - `feed(_:)`: lượt 1 của bộ luật cho một chương (`Stream.feed`); `feedLAC(_:)`: nhãn LAC của chương đó.
/// - `snapshot(chaptersRead:)`: lượt 2 + luật + phía LAC + hợp trên **toàn bộ** phần đã đọc. Không sửa trạng thái cộng
///   dồn ⇒ chụp bao nhiêu lần giữa chừng, lần chụp cuối vẫn y như chạy một lần. `nil` ⇒ task bị huỷ.
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
        /// Thời gian phía LAC (chuẩn hoá + lọc + hợp); 0 ở đường lùi.
        let lacFilterMs: Int
        /// Số danh xưng (`titles`) lúc chụp.
        let titleCount: Int
        /// Có model LAC: lý do bỏ của **bộ luật** (log riêng — `snapshot.droppedByReason` là của phía LAC). `nil` ở đường
        /// lùi (khi đó `snapshot.droppedByReason` là của bộ luật).
        let ruleDroppedByReason: [String: Int]?
        let unionAdded: Int
        /// Số hàng luật (e) giữ lại.
        let rescued: Int
    }

    private let setup: LocalNameFilterSetup
    private let dictionaries: LocalNameFilterDictionaries
    private let accumulator: LocalNameFilterAccumulator
    private let lacCounts: LocalNameFilterLACCounts?
    private let properNames: LocalNameFilterProperNames

    /// `latinModel`: mô hình đoán tên Latin khi cấu hình bật "Ưu tiên tên Latin" và nạp được; `nil` ⇒ nghĩa như tắt
    /// (không chọn nghĩa Latin, không đoán; tập chữ phiên âm đóng trong app vẫn dùng để nhận mảnh tên chữ Latin).
    init(
        configuration: LocalNameFilter.Configuration,
        dictionaries: LocalNameFilterDictionaries,
        usesLAC: Bool,
        latinModel: LocalNameFilterLatinModel? = nil
    ) {
        let setup = LocalNameFilterSetup(configuration: configuration, dictionaries: dictionaries, rulesV3: usesLAC)
        self.setup = setup
        self.dictionaries = dictionaries
        accumulator = LocalNameFilterAccumulator(setup: setup)
        lacCounts = usesLAC ? LocalNameFilterLACCounts() : nil
        properNames = LocalNameFilterProperNames(
            dictionaries: dictionaries,
            latinModel: configuration.prefersLatinNames ? latinModel : nil,
            prefixes: configuration.prefixes
        )
    }

    var hanCount: Int { accumulator.hanCount }
    var usesLAC: Bool { lacCounts != nil }
    var lacTaggedLines: Int { lacCounts?.taggedLines ?? 0 }
    /// Đang chọn nghĩa Latin + đoán (bật "Ưu tiên tên Latin" và có mô hình).
    var prefersLatin: Bool { properNames.prefersLatin }

    func feed(_ chapterText: String) {
        accumulator.feed(chapterText)
    }

    /// Nhãn LAC của chương vừa `feed` (cùng thứ tự). Bỏ qua ở đường lùi.
    func feedLAC(_ chapter: LocalNameFilterLACChapterTagger.Chapter) {
        lacCounts?.add(chapter)
    }

    func snapshot(chaptersRead: Int) -> Report? {
        let passTwoStart = DispatchTime.now().uptimeNanoseconds
        guard let occurrences = LocalNameFilterOccurrences.scan(accumulator, setup: setup, dictionaries: dictionaries) else {
            return nil
        }
        let rulesStart = DispatchTime.now().uptimeNanoseconds
        let counter = LocalNameFilterTextCounter(accumulator: accumulator)
        let meanings = LocalNameFilterMeaningBuilder(setup: setup, dictionaries: dictionaries, properNames: properNames)
        guard let decided = decide(occurrences, counter: counter, meanings: meanings) else { return nil }
        let lacStart = DispatchTime.now().uptimeNanoseconds
        let builder = LocalNameFilterOutputBuilder(setup: setup, meanings: meanings)

        let result: LocalNameFilterOutputBuilder.Result
        var rescued = 0
        if let lacCounts {
            let pipeline = LocalNameFilterLACPipeline(
                setup: setup, dictionaries: dictionaries, counts: lacCounts, counter: counter, titles: occurrences.titles
            )
            guard let lac = pipeline.run() else { return nil }
            rescued = lac.rescued
            result = builder.withLAC(lac, ruleRows: decided.rows, counts: lacCounts, titles: occurrences.titles,
                                     chaptersRead: chaptersRead)
        } else {
            result = builder.rulesOnly(decided.rows, reasons: decided.reasons, chaptersRead: chaptersRead)
        }
        if Task.isCancelled { return nil }
        let end = DispatchTime.now().uptimeNanoseconds
        return Report(
            snapshot: result.snapshot,
            passTwoMs: Int((rulesStart - passTwoStart) / 1_000_000),
            rulesMs: Int((lacStart - rulesStart) / 1_000_000),
            lacFilterMs: usesLAC ? Int((end - lacStart) / 1_000_000) : 0,
            titleCount: occurrences.titles.count,
            ruleDroppedByReason: usesLAC ? decided.reasons : nil,
            unionAdded: result.unionAdded,
            rescued: rescued
        )
    }

    // MARK: - decide

    /// `decide(s)` của Python (`KEEP_KNOWN = True`): từ thường ⇒ bỏ; thử từng cách hiểu theo `KIND_ORDER` (cùng loại thì
    /// `extra` lớn trước), lấy cách đầu tiên qua luật; name **đã có** giữ cả khi mọi cách hiểu bị luật bỏ (lấy cách hiểu
    /// đầu tiên); luật gắn lại Nhân vật; dựng nghĩa. "Không phải name" / "Loại cần tìm" / sắp xếp ở
    /// `LocalNameFilterOutputBuilder`.
    private func decide(
        _ occurrences: LocalNameFilterOccurrences,
        counter: LocalNameFilterTextCounter,
        meanings: LocalNameFilterMeaningBuilder
    ) -> (rows: [LocalNameFilterOutputBuilder.RuleRow], reasons: [String: Int])? {
        let checker = LocalNameFilterRuleChecker(
            setup: setup, dictionaries: dictionaries, occurrences: occurrences, counter: counter,
            boundness: LocalNameFilterSurnameBoundness(accumulator: accumulator, dictionaries: dictionaries)
        )
        var reasons: [String: Int] = [:]
        var rows: [LocalNameFilterOutputBuilder.RuleRow] = []

        for (index, term) in occurrences.survivors.enumerated() {
            if index & 255 == 0, Task.isCancelled { return nil }
            let count = Int(occurrences.occurrences[index])
            guard count >= setup.minCount else { continue }
            let status = dictionaries.status(term)
            if status == .common {
                reasons[Reason.dictCommonWord, default: 0] += 1
                continue
            }
            guard let stats = accumulator.stats[term] else { continue }

            var options: [(kind: LocalNameFilter.Kind, extra: Int)] = []
            for (order, kind) in LocalNameFilterRules.kindOrder.enumerated() {
                for extra in stride(from: 2, through: 1, by: -1)
                where stats.kinds & LocalNameFilterRules.kindBit(order: order, extra: extra) != 0 {
                    options.append((kind, extra))
                }
            }
            var passed: [(kind: LocalNameFilter.Kind, extra: Int)] = []
            var firstFailure: String?
            for option in options {
                if let reason = checker.check(index, term: term, kind: option.kind, extra: option.extra, count: count) {
                    if firstFailure == nil { firstFailure = reason }
                } else {
                    passed.append(option)
                }
            }
            if passed.isEmpty, status == .known, let first = options.first { passed = [first] }
            guard var chosen = passed.first else {
                if let firstFailure { reasons[firstFailure, default: 0] += 1 }
                continue
            }
            if chosen.kind != .person, let person = passed.first(where: { $0.kind == .person }),
               shouldPreferPerson(index, term: term, chosenExtra: chosen.extra, occurrences: occurrences) {
                chosen = person
            }

            let built = meanings.meaning(term: term, kind: chosen.kind, extra: chosen.extra, titles: occurrences.titles)
            rows.append(LocalNameFilterOutputBuilder.RuleRow(
                term: term,
                name: LocalNameFilter.Name(
                    term: term.string,
                    meaning: built.meaning,
                    kind: chosen.kind,
                    count: count,
                    chapterCount: Int(stats.chapters),
                    title: built.title?.string,
                    isGuessedMeaning: built.isGuessed
                ),
                isKnown: status == .known
            ))
        }
        return (rows, reasons)
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
