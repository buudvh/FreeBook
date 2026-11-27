import Foundation

/// Bước 2–4 của phía LAC trong bản thử `lacpipe.py` (`Docs/Plans/local-name-filter-lac/`), chạy lại trên **toàn bộ**
/// phần đã đọc mỗi lần chụp (không sửa `LocalNameFilterLACCounts`):
///
/// 2. Chuẩn hoá: bóc ≤ 2 chữ nhẹ cuối (穆小鱼道 → 穆小鱼) khi phần trước cũng là thực thể; tên + 1 chữ mà phần tên mạnh
///    ≥ 5 lần (李印生|盘) ⇒ gộp về tên, trừ khi chữ cuối là đuôi (mọi loại); mảnh nằm trong cụm dài ≥ 60 % số lần ⇒ mảnh.
/// 3. Lọc: mảnh; < "Ít nhất N lần"; **đã có** (Name / nghĩa đầu VP viết hoa) ⇒ giữ, đánh dấu, không qua luật sau; nghĩa
///    đầu viết thường ⇒ bỏ (`dict_common_word`) trừ luật (e) — có đuôi không yếu, ≥ 3 chữ, LAC gắn thực thể nhiều hơn
///    nhãn khác (菩提丹, 青山县); hư từ; đầu 2 chữ là từ thường; họ + từ thường; thực thể mạnh hơn hẳn + phần thừa vô
///    nghĩa (`glued_fragment`).
/// 4. Loại: đuôi dò dài nhất (place / sect / term, bộ cố định — cách A) rồi nhãn LAC nhiều nhất; LAC bảo người + chữ cuối
///    là đuôi yếu (山 河…) + loại địa danh / tổ chức ⇒ vẫn là người (费渊). Nghĩa dựng sau, theo danh sách người dùng
///    (`LocalNameFilterMeaningBuilder`).
///
/// Tên lý do bỏ trùng `lacpipe.py`. Đếm số lần trong truyện: từ toàn chữ Hán dải bộ luật ⇒ chỉ mục của bộ luật
/// (`LocalNameFilterTextCounter`), từ khác ⇒ chuỗi các dòng của phía LAC.
struct LocalNameFilterLACPipeline {
    typealias Word = LocalNameFilterWord
    typealias Tally = LocalNameFilterLACCounts.Tally
    typealias SuffixMatch = (length: Int, suffix: LocalNameFilter.Suffix)
    private typealias Reason = LocalNameFilterRules.Reason
    private typealias Rules = LocalNameFilterRules

    struct Row {
        let word: Word
        let kind: LocalNameFilter.Kind
        let count: Int
        let chapterCount: Int
        let isKnown: Bool
    }

    struct Output {
        var rows: [Row] = []
        /// `fragment_of` — bước hợp bỏ hàng bộ luật là mảnh.
        var fragments = Set<Word>()
        var reasons: [String: Int] = [:]
        /// Số hàng luật (e) giữ lại (chỉ để log).
        var rescued = 0
    }

    let setup: LocalNameFilterSetup
    let dictionaries: LocalNameFilterDictionaries
    let counts: LocalNameFilterLACCounts
    let counter: LocalNameFilterTextCounter

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
            let status = dictionaries.status(word: word)
            let suffix = setup.lacSuffix(of: word)
            let row = { (isKnown: Bool) in
                Row(word: word, kind: kind(of: word, suffix: suffix, tag: tally.dominant), count: count,
                    chapterCount: chapterCount(of: sources[word] ?? [word], entities: entities), isKnown: isKnown)
            }
            if status == .known {
                output.rows.append(row(true))
                continue
            }
            if status == .common, !isRescued(word, suffix: suffix, entities: entities) {
                output.reasons[Reason.dictCommonWord, default: 0] += 1
                continue
            }
            if let reason = check(word, count: count, merged: merged) {
                output.reasons[reason, default: 0] += 1
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

    /// Luật (e): VP nghĩa thường nhưng có đuôi không yếu, ≥ 3 chữ, LAC gắn thực thể nhiều hơn nhãn khác (đếm thô).
    private func isRescued(_ word: Word, suffix: SuffixMatch?, entities: [Word: LocalNameFilterLACCounts.Entry]) -> Bool {
        guard suffix != nil, word.count >= 3, !Rules.has(scalar: word.last, .weakSuffix) else { return false }
        return (entities[word]?.tally.total ?? 0) > (counts.others[word] ?? 0)
    }

    /// Các luật sau "từ thường", đúng thứ tự `lacpipe.py`. `nil` = qua.
    private func check(_ word: Word, count: Int, merged: [Word: Tally]) -> String? {
        if word.scalars.contains(where: { Rules.has(scalar: $0, .lacFunction) }) { return Reason.functionChar }
        if word.count == 3 {
            // Đầu 2 chữ là từ thường đứng riêng nhiều hơn hẳn (许久|之, 周身|魂); họ kép (上官|博) không tính.
            let head = word.slice(0, 2)
            if !isSurname(head), dictionaries.status(word: head) == .common,
               Double(textCount(head)) >= Rules.commonPartRatio * Double(textCount(word)) {
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

    /// `glued_fragment`: trong cụm có thực thể (không phải họ) mạnh ≥ 3 lần cụm, phần thừa không phải danh xưng và là
    /// một chữ / có hư từ / có từ thường (宁天|目光, 尘|心中|君亭, 比|林宇). Phần thừa là danh xưng thì giữ (林砚|公子).
    private func isGlued(_ word: Word, count: Int, merged: [Word: Tally]) -> Bool {
        let length = word.count
        guard length >= 3 else { return false }
        for innerLength in stride(from: length - 1, through: 2, by: -1) {
            for start in 0...(length - innerLength) {
                let inner = word.slice(start, start + innerLength)
                guard !isSurname(inner), let tally = merged[inner],
                      Int(tally.total) >= Rules.lacGlueStrength * count else { continue }
                let rest = word.removing(from: start, length: innerLength)
                if isPronoun(rest) { continue }
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

    // MARK: - 4. Loại

    private func kind(of word: Word, suffix: SuffixMatch?, tag: LocalNameFilter.Category) -> LocalNameFilter.Kind {
        guard let suffix else { return Self.kind(for: tag) }
        let kind = Self.kind(for: suffix.suffix.kind)
        if tag == .person, Rules.has(scalar: word.last, .weakSuffix), kind == .place || kind == .sect {
            return .person
        }
        return kind
    }

    static func kind(for category: LocalNameFilter.Category) -> LocalNameFilter.Kind {
        switch category {
        case .person: return .person
        case .place: return .place
        case .organization: return .sect
        case .term: return .term
        }
    }

    static func kind(for suffixKind: LocalNameFilter.SuffixKind) -> LocalNameFilter.Kind {
        switch suffixKind {
        case .place: return .place
        case .sect: return .sect
        case .term: return .term
        }
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

    /// `rest in PRONOUNS` (khoá Pronouns ≥ 2 chữ).
    private func isPronoun(_ word: Word) -> Bool {
        guard word.count >= 2, let key = word.termKey else { return false }
        return dictionaries.pronounEntries?[key] != nil
    }

    private func textCount(_ word: Word) -> Int {
        if let units = word.ruleHanUnits { return counter.count(units: units) }
        return counts.countInFullText(word.utf16Units)
    }
}
