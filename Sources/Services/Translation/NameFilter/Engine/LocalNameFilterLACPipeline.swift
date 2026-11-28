import Foundation

/// Bước 2–4 của phía LAC trong bản thử `lacpipe.py` (`Docs/Plans/local-name-filter-lac/`), chạy lại trên **toàn bộ**
/// phần đã đọc mỗi lần chụp (không sửa `LocalNameFilterLACCounts`):
///
/// 2. Chuẩn hoá: bóc ≤ 2 chữ nhẹ cuối (穆小鱼道 → 穆小鱼) khi phần trước cũng là thực thể; tên + 1 chữ mà phần tên mạnh
///    ≥ 5 lần (李印生|盘) ⇒ gộp về tên, trừ khi chữ cuối là đuôi (mọi loại); mảnh nằm trong cụm dài ≥ 60 % số lần ⇒ mảnh.
/// 3. Lọc: mảnh; < "Ít nhất N lần"; L5 số + 阶 / 级 / 品 ở đầu (`rank_prefix`, cả name đã có: 九阶, 九阶妖王); **đã có**
///    (Name / nghĩa đầu VP viết hoa) ⇒ giữ, đánh dấu, không qua luật sau; nghĩa đầu viết thường ⇒ bỏ (`dict_common_word`)
///    trừ luật (e) — có đuôi không yếu (không tính hậu tố Nhân danh), ≥ 3 chữ, LAC gắn thực thể nhiều hơn nhãn khác
///    (菩提丹, 青山县); hư từ; đầu 2 chữ là từ thường; họ + từ thường; thực thể mạnh hơn hẳn + phần thừa vô nghĩa
///    (`glued_fragment` — phần thừa là một hậu tố ≥ 2 chữ của danh sách người dùng, mọi loại, thì giữ).
/// 3b. Đợt 4 (2026-11-28, file `+Bound`): cụm qua hết luật trên mà LAC cắt cụt ⇒ nối chữ dính trái / phải (寒尸冥 → 寒尸冥将,
///    情谷 → 问情谷) hoặc bỏ (`bound_glued`); cụm đã nối xét lại "đã là thực thể khác" (`bound_merged`), từ thường,
///    `glued_fragment`. Luật "đầu 2 chữ là từ thường" (K) chỉ tính phần đầu **không** nằm trong thực thể 3 chữ nào mở đầu
///    bằng nó (沈清瑶: VP có 沈清 = "trầm thanh" nhưng 沈清 chỉ nằm trong 沈清瑶 / 沈清霜… ⇒ không bỏ).
/// 4. Loại (`kind(of:…)`, file `+Kind`): L11 / L1–L4 / L16 của plan 2026-11-27-phan-loai-name. Nghĩa dựng sau, theo danh sách
///    người dùng (`LocalNameFilterMeaningBuilder`).
///
/// Tên lý do bỏ trùng `lacpipe.py`. Đếm số lần trong truyện: từ toàn chữ Hán dải bộ luật ⇒ chỉ mục của bộ luật
/// (`LocalNameFilterTextCounter`), từ khác ⇒ chuỗi các dòng của phía LAC.
struct LocalNameFilterLACPipeline {
    typealias Word = LocalNameFilterWord
    typealias Tally = LocalNameFilterLACCounts.Tally
    typealias SuffixMatch = (length: Int, suffix: LocalNameFilter.Suffix)
    private typealias Reason = LocalNameFilterRules.Reason
    typealias Rules = LocalNameFilterRules

    struct Row {
        let word: Word
        let kind: LocalNameFilter.Kind
        let count: Int
        let chapterCount: Int
        let isKnown: Bool
        /// Đợt 4: danh xưng lấy từ từ điển cho riêng hàng này — cụm được nối đúng một chữ bên phải mà cặp "chữ cuối + chữ
        /// nối" có trong từ điển (寒尸冥 + 将: 冥将 = "Minh Tướng"). `LocalNameFilterMeaningBuilder` chỉ dùng khi danh sách
        /// hậu tố không có danh xưng nào khớp.
        var dictionaryTitle: Word? = nil
    }

    struct Output {
        var rows: [Row] = []
        /// `fragment_of` — bước hợp bỏ hàng bộ luật là mảnh.
        var fragments = Set<Word>()
        var reasons: [String: Int] = [:]
        /// Số hàng luật (e) giữ lại (chỉ để log).
        var rescued = 0
        /// Đợt 4: số hàng là cụm đã nối (chỉ để log).
        var extended = 0
    }

    let setup: LocalNameFilterSetup
    let dictionaries: LocalNameFilterDictionaries
    let counts: LocalNameFilterLACCounts
    let counter: LocalNameFilterTextCounter
    /// Danh xưng của bộ luật lúc chụp (`Snapshot.titles`) — danh xưng 1 chữ của luật phân loại ("có danh xưng").
    let titles: Set<LocalNameFilterTermKey>
    /// Phần tên riêng của lượt (tiền tố + tập chữ phiên âm + âm Hán-Việt) — lõi Latin của luật phân loại L16.
    let properNames: LocalNameFilterProperNames

    /// `nil` ⇒ task bị huỷ giữa chừng.
    func run() -> Output? {
        let entities = counts.entities
        var merged: [Word: Tally] = [:]
        var sources: [Word: [Word]] = [:]
        for (word, entry) in entities {
            let target = mergeTarget(word, total: entry.tally.total, entities: entities)
            merged[target, default: Tally()].merge(entry.tally)
            sources[target, default: []].append(word)
        }
        if Task.isCancelled { return nil }
        guard let fragments = findFragments(merged) else { return nil }
        // Đợt 4: danh xưng suy ra (`INFERRED_TITLES`), bảng "đầu 2 chữ ⇒ thực thể 3 chữ" (`SIBLINGS`), cụm đã nối (`EXTENDED`).
        guard let inferred = inferredTitles(merged) else { return nil }
        var siblings: [Word: [Word]] = [:]
        for word in merged.keys where word.count == 3 { siblings[word.slice(0, 2), default: []].append(word) }
        var extendedWords = Set<Word>()

        var output = Output()
        output.fragments = fragments
        for (index, (word, tally)) in merged.enumerated() {
            if index & 511 == 0, Task.isCancelled { return nil }
            let count = Int(tally.total)
            if fragments.contains(word) {
                output.reasons[Reason.fragment, default: 0] += 1
                continue
            }
            if count < setup.minCount {
                output.reasons[Reason.minCount, default: 0] += 1
                continue
            }
            if Rules.isRankPrefix(word) {
                output.reasons[Reason.rankPrefix, default: 0] += 1
                continue
            }
            let status = dictionaries.status(word: word)
            let suffix = setup.lacSuffix(of: word)
            let row = { (isKnown: Bool) in
                Row(word: word, kind: kind(of: word, suffix: suffix, tag: tally.dominant, entities: entities),
                    count: count, chapterCount: chapterCount(of: sources[word] ?? [word], entities: entities),
                    isKnown: isKnown)
            }
            if status == .known {
                output.rows.append(row(true))
                continue
            }
            if status == .common, !isRescued(word, entities: entities) {
                output.reasons[Reason.dictCommonWord, default: 0] += 1
                continue
            }
            if let reason = check(word, count: count, merged: merged, siblings: siblings) {
                output.reasons[reason, default: 0] += 1
                continue
            }
            // Đợt 4: LAC cắt cụt ⇒ nối chữ dính (`+Bound`).
            guard let target = boundTarget(word, tag: tally.dominant, inferred: inferred) else {
                output.reasons[Reason.boundGlued, default: 0] += 1
                continue
            }
            if target != word {
                if merged[target] != nil || extendedWords.contains(target) {
                    output.reasons[Reason.boundMerged, default: 0] += 1
                    continue
                }
                let targetStatus = dictionaries.status(word: target)
                if targetStatus == .common {
                    output.reasons[Reason.dictCommonWord, default: 0] += 1
                    continue
                }
                if isGlued(target, count: count, merged: merged) {
                    output.reasons[Reason.gluedFragment, default: 0] += 1
                    continue
                }
                extendedWords.insert(target)
                let targetKind = kind(of: target, suffix: setup.lacSuffix(of: target), tag: tally.dominant,
                                      entities: entities, statsOf: word)
                var title: Word?
                if targetKind == .person, word.count >= 3, target.count == word.count + 1, target.dropLast(1) == word,
                   dictionaries.status(word: target.suffix(2)) != nil {
                    title = target.suffix(2)
                }
                output.rows.append(Row(word: target, kind: targetKind, count: count,
                                       chapterCount: chapterCount(of: sources[word] ?? [word], entities: entities),
                                       isKnown: targetStatus == .known, dictionaryTitle: title))
                output.extended += 1
                continue
            }
            if status == .common { output.rescued += 1 }
            output.rows.append(row(false))
        }
        return output
    }

    // MARK: - 2. Chuẩn hoá

    private func mergeTarget(_ word: Word, total: Int32, entities: [Word: LocalNameFilterLACCounts.Entry]) -> Word {
        for trail in 1...2 {
            let base = word.dropLast(trail)
            guard base.count >= 2,
                  (word.count - trail..<word.count).allSatisfy({ Rules.has(scalar: word[$0], .trailLight) }),
                  entities[base] != nil else { continue }
            return base
        }
        if word.count >= 3, !setup.lacSuffixChars.contains(word.last),
           let head = entities[word.dropLast(1)], head.tally.total >= Rules.lacHeadStrength * total {
            return word.dropLast(1)
        }
        return word
    }

    /// `fragment_of`: `w` là mảnh khi có cụm dài hơn (cũng là thực thể) chứa nó với số lần ≥ 60 % số lần của `w`.
    /// Duyệt theo cụm dài: mỗi chuỗi con ≥ 2 chữ là thực thể nhận số lần lớn nhất của cụm chứa nó.
    private func findFragments(_ merged: [Word: Tally]) -> Set<Word>? {
        var bestContaining: [Word: Int] = [:]
        for (index, longer) in merged.keys.enumerated() where longer.count >= 3 {
            if index & 255 == 0, Task.isCancelled { return nil }
            var contained: [Word] = []
            for length in 2..<longer.count {
                for start in 0...(longer.count - length) {
                    let piece = longer.slice(start, start + length)
                    if merged[piece] != nil { contained.append(piece) }
                }
            }
            guard !contained.isEmpty else { continue }
            let longerCount = textCount(longer)
            for piece in contained where longerCount > (bestContaining[piece] ?? -1) {
                bestContaining[piece] = longerCount
            }
        }
        var fragments = Set<Word>()
        for (piece, best) in bestContaining {
            let own = textCount(piece)
            if own > 0, Double(best) >= Rules.lacFragmentRatio * Double(own) { fragments.insert(piece) }
        }
        return fragments
    }

    // MARK: - 3. Lọc

    /// Luật (e): VP nghĩa thường nhưng có đuôi không yếu (đuôi dò địa danh / tổ chức / thuật ngữ — không tính hậu tố
    /// Nhân danh), ≥ 3 chữ, LAC gắn thực thể nhiều hơn nhãn khác (đếm thô).
    private func isRescued(_ word: Word, entities: [Word: LocalNameFilterLACCounts.Entry]) -> Bool {
        guard setup.lacRescueSuffix(of: word) != nil, word.count >= 3, !Rules.has(scalar: word.last, .weakSuffix) else {
            return false
        }
        return (entities[word]?.tally.total ?? 0) > (counts.others[word] ?? 0)
    }

    /// Các luật sau "từ thường", đúng thứ tự `lacpipe.py`. `nil` = qua.
    private func check(_ word: Word, count: Int, merged: [Word: Tally], siblings: [Word: [Word]]) -> String? {
        if word.scalars.contains(where: { Rules.has(scalar: $0, .lacFunction) }) { return Reason.functionChar }
        if word.count == 3 {
            // Đầu 2 chữ là từ thường đứng riêng nhiều hơn hẳn (许久|之, 周身|魂); họ kép (上官|博) không tính. Đợt 4 (K): "đứng
            // riêng" = không nằm trong thực thể 3 chữ nào mở đầu bằng nó (沈清瑶 / 沈清霜 / 沈清璇 dùng chung đầu 沈清).
            let head = word.slice(0, 2)
            if !isSurname(head), dictionaries.status(word: head) == .common,
               Double(standaloneCount(head, siblings: siblings)) >= Rules.commonHeadStandaloneRatio * Double(textCount(word)) {
                return Reason.dictCommonHead
            }
            // Họ đơn + từ thường 2 chữ (王|余孽).
            let given = word.slice(1, 3)
            if isSurname(word.slice(0, 1)), dictionaries.status(word: given) == .common,
               Double(textCount(given)) >= Rules.commonPartRatio * Double(textCount(word)) {
                return Reason.dictCommonGiven
            }
        }
        return isGlued(word, count: count, merged: merged) ? Reason.gluedFragment : nil
    }

    /// (K) `standalone_head(w)`: số lần `head` xuất hiện trừ số lần của mọi thực thể 3 chữ mở đầu bằng nó.
    private func standaloneCount(_ head: Word, siblings: [Word: [Word]]) -> Int {
        var count = textCount(head)
        for sibling in siblings[head] ?? [] { count -= textCount(sibling) }
        return count
    }

    /// `glued_fragment`: trong cụm có thực thể (không phải họ) mạnh ≥ 3 lần cụm, phần thừa không phải hậu tố và là một chữ /
    /// có hư từ / có từ thường (宁天|目光, 尘|心中|君亭, 比|林宇). Phần thừa là một hậu tố ≥ 2 chữ của danh sách người dùng,
    /// mọi loại, thì giữ (林砚|公子, 东阳|酒店, 贝克兰德|大学 — plan 2026-11-27-phan-loai-name L11).
    private func isGlued(_ word: Word, count: Int, merged: [Word: Tally]) -> Bool {
        let length = word.count
        guard length >= 3 else { return false }
        for innerLength in stride(from: length - 1, through: 2, by: -1) {
            for start in 0...(length - innerLength) {
                let inner = word.slice(start, start + innerLength)
                guard !isSurname(inner), let tally = merged[inner],
                      Int(tally.total) >= Rules.lacGlueStrength * count else { continue }
                let rest = word.removing(from: start, length: innerLength)
                if setup.isGlueKeep(rest) { continue }
                let parts = [word.slice(0, start), word.slice(start + innerLength, length)].filter { !$0.isEmpty }
                let commonInside = parts.contains { part in
                    (0..<max(0, part.count - 1)).contains { dictionaries.status(word: part.slice($0, $0 + 2)) == .common }
                }
                if rest.count == 1 || commonInside
                    || rest.scalars.contains(where: { Rules.has(scalar: $0, .lacFunction) })
                    || parts.contains(where: { dictionaries.status(word: $0) == .common }) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Tra

    private func chapterCount(of words: [Word], entities: [Word: LocalNameFilterLACCounts.Entry]) -> Int {
        if words.count == 1 { return entities[words[0]]?.chapters.count ?? 0 }
        var chapters = Set<Int32>()
        for word in words { chapters.formUnion(entities[word]?.chapters ?? []) }
        return chapters.count
    }

    private func isSurname(_ word: Word) -> Bool {
        word.termKey.map { dictionaries.surnames[$0] != nil } ?? false
    }

    private func textCount(_ word: Word) -> Int {
        if let units = word.ruleHanUnits { return counter.count(units: units) }
        return counts.countInFullText(word.utf16Units)
    }
}
