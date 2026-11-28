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
/// 3c. Đợt 5 (2026-11-28, "đủ name" — soát mọi thực thể bị bỏ trên 11 truyện): `dict_common_given` không áp cho họ + hậu tố
///    Nhân danh (陈真传) và chỉ khi LAC tách phần sau họ thành từ thường ≥ 3 × số lần của cụm (江明月 642 lần, 柯大力 631 lần
///    từng bị bỏ); `dict_common_head` không áp cho cụm có hậu tố dò ≥ 5 lần (大力盟, 如意坊); `function_char` bỏ qua 会 cuối,
///    哈, 地 không cuối và 9 chữ trong tên "họ + tên" (云梦商会, 哈迪伯爵, 于斯年, 裴问心); `glued_fragment` giữ thực thể + một
///    chữ đuôi không dính phải / chữ thân tộc và 小 老 阿 + thực thể (史莱克城, 林戎兄, 小炽翎); mảnh: tên mở đầu bằng họ đứng sau
///    biệt hiệu ≥ 2 chữ không phải mảnh (剑圣|叶瞻); từ thường: nghĩa VP có từ viết hoa ở giữa ⇒ đã có (老尼尔 = "lão Neil"), họ
///    + hậu tố Nhân danh ≥ 2 chữ không bị bỏ (武师兄).
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
            var status = dictionaries.status(word: word)
            // Đợt 5 (W): nghĩa đầu viết thường nhưng có từ viết hoa (老尼尔 = "lão Neil", 临州城 = "thành Lâm Châu") ⇒ đã có.
            if status == .common, dictionaries.hasInnerCapital(word: word) { status = .known }
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
            // Đợt 5 (W): họ + hậu tố Nhân danh ≥ 2 chữ của danh sách (武师兄) — VP ghi cả cụm viết thường vẫn là name.
            if status == .common, tally.dominant == .person, isSurnameWithTitle(word) { status = nil }
            if status == .common, !isRescued(word, entities: entities) {
                output.reasons[Reason.dictCommonWord, default: 0] += 1
                continue
            }
            if let reason = check(word, count: count, tag: tally.dominant, hasSuffix: suffix != nil, merged: merged,
                                  siblings: siblings) {
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
                    // Đợt 5 (FR): tên mở đầu bằng họ đứng ở cuối cụm sau một biệt hiệu ≥ 2 chữ (剑圣|叶瞻) không phải mảnh.
                    if merged[piece] != nil,
                       !(start + length == longer.count && isNameAfterTitle(piece, in: longer)) {
                        contained.append(piece)
                    }
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
    private func check(
        _ word: Word,
        count: Int,
        tag: LocalNameFilter.Category,
        hasSuffix: Bool,
        merged: [Word: Tally],
        siblings: [Word: [Word]]
    ) -> String? {
        if hasFunctionChar(word, tag: tag, count: count) { return Reason.functionChar }
        if word.count == 3 {
            // Đầu 2 chữ là từ thường đứng riêng nhiều hơn hẳn (许久|之, 周身|魂); họ kép (上官|博) không tính. Đợt 4 (K): "đứng
            // riêng" = không nằm trong thực thể 3 chữ nào mở đầu bằng nó (沈清瑶 / 沈清霜 / 沈清璇 dùng chung đầu 沈清).
            let head = word.slice(0, 2)
            // Đợt 5 (H): cụm có hậu tố dò và ≥ 5 lần (大力盟, 如意坊, 神龙城) là từ thường + hậu tố = name, không xét.
            if !hasSuffix || count < Rules.commonHeadSuffixMinCount, !isSurname(head),
               dictionaries.status(word: head) == .common,
               Double(standaloneCount(head, siblings: siblings)) >= Rules.commonHeadStandaloneRatio * Double(textCount(word)) {
                return Reason.dictCommonHead
            }
            // Họ đơn + từ thường 2 chữ (王|余孽).
            let given = word.slice(1, 3)
            // Đợt 5 (G): phần sau họ không phải hậu tố Nhân danh (陈真传), và LAC tách nó thành từ thường đứng riêng ≥ 3 × số
            // lần của cụm (王|余孽 bỏ; 江明月, 柯大力 giữ).
            if isSurname(word.slice(0, 1)), dictionaries.status(word: given) == .common,
               Double(textCount(given)) >= Rules.commonPartRatio * Double(textCount(word)),
               !setup.isPersonSuffix(given),
               Int(counts.others[given] ?? 0) >= Rules.commonGivenStandaloneFactor * count {
                return Reason.dictCommonGiven
            }
        }
        return isGlued(word, count: count, merged: merged) ? Reason.gluedFragment : nil
    }

    /// (F) `has_function_char(w, lac_tag)`: có hư từ phía LAC, trừ 会 ở cuối cụm ≥ 3 chữ (商会, 教会, 协会), 哈 khi không có 哈哈
    /// (phiên âm: 哈迪, 哈布拉), 地 không ở cuối (遁地术, 大地母神), và các chữ `functionNameOKScalars` trong tên người 2–3 chữ mở
    /// đầu bằng họ đơn (于斯年, 裴问心, 石良才).
    private func hasFunctionChar(_ word: Word, tag: LocalNameFilter.Category, count: Int) -> Bool {
        let scalars = word.scalars
        let last = scalars.count - 1
        let personShape = tag == .person && (2...3).contains(scalars.count) && isSingleSurname(scalars[0])
        var hasDoubleHa = false
        if last >= 1 {
            for index in 0..<last where scalars[index] == Rules.haScalar && scalars[index + 1] == Rules.haScalar {
                hasDoubleHa = true
            }
        }
        for (index, scalar) in scalars.enumerated() where Rules.has(scalar: scalar, .lacFunction) {
            if scalar == Rules.huiScalar, index == last, scalars.count >= 3 { continue }
            if scalar == Rules.haScalar, !hasDoubleHa { continue }
            if scalar == Rules.diScalar, index < last { continue }
            if personShape, Rules.functionNameOKScalars.contains(scalar) {
                // Đợt 7 (kiểm trên máy 1.3.1139: 穆宣和 = 穆宣 + "và"): chữ cuối của cụm 3 chữ mà hai chữ đầu đã là thực thể
                // LAC xuất hiện ít nhất bằng chính cụm (và đủ "Ít nhất N lần") ⇒ hư từ đứng sau tên. 石良才 (石良 ít hơn) giữ.
                if index == last, scalars.count == 3,
                   Int(counts.entities[word.dropLast(1)]?.tally.total ?? 0) >= max(setup.minCount, count) {
                    return true
                }
                continue
            }
            return true
        }
        return false
    }

    /// (W) Họ + hậu tố Nhân danh ≥ 2 chữ của danh sách người dùng (武师兄).
    private func isSurnameWithTitle(_ word: Word) -> Bool {
        let surnameLength = dictionaries.surnameLength(of: word)
        guard surnameLength > 0, word.count - surnameLength >= 2 else { return false }
        return setup.isPersonSuffix(word.slice(surnameLength, word.count))
    }

    /// (FR) `name_after_title(w, longer)`: `piece` mở đầu bằng họ đơn, đứng ở cuối `longer` sau một phần ≥ 2 chữ không phải
    /// họ; LAC gắn `piece` là thực thể nhiều hơn nhãn thường và nó không kết thúc bằng 儿 / 子 (成神, 孙儿 không tính).
    private func isNameAfterTitle(_ piece: Word, in longer: Word) -> Bool {
        guard piece.count >= 2, isSingleSurname(piece[0]) else { return false }
        let entity = counts.entities[piece]?.tally.total ?? 0
        if (counts.others[piece] ?? 0) >= entity || Rules.commonKeepEndScalars.contains(piece.last) { return false }
        let head = longer.dropLast(piece.count)
        return head.count >= 2 && !isSurname(head)
    }

    private func isSingleSurname(_ scalar: UInt32) -> Bool {
        scalar <= 0xFFFF && setup.has(UInt16(scalar), .surnameSingle)
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
                // Đợt 5 (GL): thực thể + đúng một chữ thân tộc / chữ đuôi dò ở cuối (林戎|兄, 史莱克|城 — đuôi thì cụm không được
                // dính chữ ngay sau: 临济城镇|魔司), hoặc 小 / 老 / 阿 + thực thể (小|炽翎).
                if rest.count == 1 {
                    let only = rest[0]
                    if start == 0, Rules.has(scalar: only, .kinship) { continue }
                    if start == 1, Rules.gluePrefixScalars.contains(only) { continue }
                    if start == 0, setup.lacSuffixChars.contains(only), !isBoundRight(word) { continue }
                }
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
