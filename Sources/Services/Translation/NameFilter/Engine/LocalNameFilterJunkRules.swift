import Foundation

/// Luật rác L17–L22 của đường có model LAC — `junk_reason` của `lacpipe.py` (khối "Luật rác (2026-11-28…)", anh Bửu duyệt;
/// đo trên danh sách "Không phải name" 137 cụm của anh). Bản Python trên 11 truyện: bỏ 85 hàng (đều rác / name ghép),
/// không thêm, không đổi nghĩa.
///
/// Chạy ở `LocalNameFilterOutputBuilder.withLAC` ngay sau L9 (`glued_names`), **chỉ** cho name chưa có (người gọi bỏ qua
/// name đã có); đường lùi "chỉ bộ luật" không có (như L5 / L9). Bảng tra `all_cat` / `count_of` dựng **một** lần từ mọi
/// hàng sau L9 — kể cả name đã có và hàng sẽ bị chính các luật này bỏ. Luật đầu tiên khớp quyết lý do, thứ tự y Python:
///
/// 1. L17 `glued_entities` — name ≥ 4 chữ = name của danh sách (≥ 2 chữ) + phần sau (≥ 2 chữ) là name của danh sách, hoặc
///    name của danh sách (≥ 2 chữ) + hậu tố dò 2 rồi 1 chữ; chỗ tách **đầu tiên** có phần trước là name quyết: phần sau không
///    phải Nhân danh ⇒ bỏ (中州|嵩云宗, 镇魔司|紫衣卫), là Nhân danh ⇒ giữ, không thử chỗ tách sau (翎王|姬桓).
/// 2. L18 `prep_head` — địa danh / tổ chức / thuật ngữ có hậu tố (hàng bộ luật: đuôi đã dò; hàng LAC: hậu tố dò dài nhất)
///    mà phần trước hậu tố đúng 1 chữ thuộc `PREP_HEAD` (朝城, 处山脉, 替宗门, 由镇, 众村, 当庄).
/// 3. L19 `repeat_or_digit` — một chữ lặp ≥ 3 lần liền, hoặc có chữ số (`str.isdigit` = Numeric_Type Decimal / Digit:
///    0–9, ０–９, ²…; chữ số Hán 一 三 万 không tính) — 铿铿铿, 小成955/1000.
/// 4. L20 `common_phrase` — Nhân danh phía LAC (không phải hàng bộ luật), không mở đầu bằng họ, phủ trọn bằng ≥ 2 từ thường
///    VP (khớp dài nhất từ trái 6 … 2 chữ, không lùi), không kết thúc bằng chữ thân tộc `KIN_TAIL` hay hậu tố Nhân danh
///    nào của danh sách người dùng (幽蓝光影, 恐怖若斯, 炽白遁光; 黑夜女神, 五鬼老三 giữ).
/// 5. L22 `verb_head` — hàng bộ luật địa danh / tổ chức có đuôi, < 20 lần, phần trước đuôi ≥ 2 chữ là từ thường VP mà LAC
///    gán đứng riêng ≥ 20 lần, ≥ 60 % nhãn thuộc `VERBISH`, chưa từng gắn nhãn thực thể (拜入宗门, 赶往宗门, 虽然海;
///    毁灭森林, 极北城, 冶炼司 giữ).
/// 6. L21 `name_fragment` — Nhân danh ≥ 3 chữ = Nhân danh khác của danh sách (≥ 100 lần) + 1 chữ, số lần < 1 % của tên
///    đó, chữ cuối và hai chữ cuối đều không phải hậu tố Nhân danh (陈诚头, 邓恩先, 宁天俏; 王家主 giữ nhờ 家主).
///
/// Đợt 3 (2026-11-28, anh Bửu "tự chọn"; Python 11 truyện bỏ thêm 30 hàng cùng L23 của bộ luật, 0 name đã có bị mất):
/// L25 `quantity_head` xét ngay sau L19 — name ≥ 3 chữ mở đầu bằng lượng từ số đông `quantityHeads` (许多大家族, 诸多大宗门,
/// 一众江湖); L24 `title_fragment` xét **sau cùng** (`title_fragment(r)` chạy khi `junk_reason` không bắt) — Nhân danh `w`
/// có hàng `w + c` (≥ 80 % số lần của `w`) mà chữ cuối hoặc hai chữ cuối của `w` + `c` là hậu tố Nhân danh ⇒ `w` là tên
/// bị cắt giữa danh xưng, tên đủ vẫn còn (萧太 ⊂ 萧太上, 离乱天 ⊂ 离乱天君).
struct LocalNameFilterJunkRules {
    typealias Word = LocalNameFilterWord
    private typealias Rules = LocalNameFilterRules
    private typealias Reason = LocalNameFilterRules.Reason

    /// Một hàng của danh sách sau L9 (`r` của Python).
    struct Row {
        let word: Word
        /// `r["cat"]`.
        let category: LocalNameFilter.Category
        /// `r["c"]`.
        let count: Int
        /// Hàng bộ luật thêm ở bước hợp (`"rule" in r`).
        let isRuleRow: Bool
        /// Hàng bộ luật: số chữ của đuôi đã dò (`rule["suffix"]` — chỉ địa danh / tổ chức), `nil` với tên người / họ tộc.
        /// Hàng LAC: bỏ qua.
        let ruleSuffixLength: Int?
    }

    private let setup: LocalNameFilterSetup
    private let dictionaries: LocalNameFilterDictionaries
    private let counts: LocalNameFilterLACCounts
    /// `all_cat`.
    private let categories: [Word: LocalNameFilter.Category]
    /// `count_of`.
    private let rowCounts: [Word: Int]
    /// L24: `w` ⇒ các hàng `w + c` của `count_of` (chữ thêm `c`, số lần) — thay vòng quét cả `count_of` của Python.
    private let extensions: [Word: [(last: UInt32, count: Int)]]

    /// `rows`: **mọi** hàng sau L9, kể cả name đã có.
    init(
        rows: [Row],
        setup: LocalNameFilterSetup,
        dictionaries: LocalNameFilterDictionaries,
        counts: LocalNameFilterLACCounts
    ) {
        self.setup = setup
        self.dictionaries = dictionaries
        self.counts = counts
        // Dict comprehension của Python: trùng khoá thì hàng sau thắng (danh sách không có khoá trùng).
        categories = Dictionary(rows.map { ($0.word, $0.category) }, uniquingKeysWith: { _, last in last })
        rowCounts = Dictionary(rows.map { ($0.word, $0.count) }, uniquingKeysWith: { _, last in last })
        var extensions: [Word: [(last: UInt32, count: Int)]] = [:]
        for (word, count) in rowCounts where word.count >= 3 {
            extensions[word.dropLast(1), default: []].append((word.last, count))
        }
        self.extensions = extensions
    }

    /// `junk_reason(r)` — tên lý do bỏ, `nil` = giữ.
    func reason(for row: Row) -> String? {
        let word = row.word
        if word.count >= Rules.gluedEntitiesMinLength, isGluedEntities(word) { return Reason.gluedEntities }
        // `(r.get("rule") or {}).get("suffix") or r.get("suf")`: hàng bộ luật chỉ có đuôi đã dò (không lùi về hậu tố dò).
        let suffixLength = row.isRuleRow ? row.ruleSuffixLength : setup.lacSuffix(of: word)?.length
        if row.category != .person, let suffixLength, word.count - suffixLength == 1,
           Rules.prepHeadScalars.contains(word[0]) {
            return Reason.prepHead
        }
        if Self.hasRepeatOrDigit(word) { return Reason.repeatOrDigit }
        if Self.hasQuantityHead(word) { return Reason.quantityHead }
        if row.category == .person, !row.isRuleRow, dictionaries.surnameLength(of: word) == 0,
           !Rules.kinTailScalars.contains(word.last), !setup.endsWithPersonSuffix(word), isCoveredByCommonWords(word) {
            return Reason.commonPhrase
        }
        if isVerbHead(row) { return Reason.verbHead }
        if isNameFragment(row) { return Reason.nameFragment }
        if isTitleFragment(row) { return Reason.titleFragment }
        return nil
    }

    // MARK: - Từng luật

    /// L17 `glued_entities(w)`.
    private func isGluedEntities(_ word: Word) -> Bool {
        guard word.count >= Rules.gluedEntitiesMinLength else { return false }
        for split in 2..<(word.count - 1) {
            guard categories[word.slice(0, split)] != nil else { continue }
            let tail = word.slice(split, word.count)
            // `b in all_cat and b != w` — `b` luôn ngắn hơn `w`.
            if let category = categories[tail] { return category != .person }
            for length in [2, 1] {
                let core = tail.dropLast(length)
                if core.count >= 2, setup.lacSuffixes[tail.suffix(length)] != nil, let category = categories[core] {
                    return category != .person
                }
            }
        }
        return false
    }

    /// L19: `w[i] == w[i + 1] == w[i + 2]` hoặc `any(ch.isdigit() for ch in w)`.
    private static func hasRepeatOrDigit(_ word: Word) -> Bool {
        if word.count >= 3 {
            for index in 0...(word.count - 3) where word[index] == word[index + 1] && word[index + 1] == word[index + 2] {
                return true
            }
        }
        return word.scalars.contains { value in
            guard let numericType = Unicode.Scalar(value)?.properties.numericType else { return false }
            return numericType == .decimal || numericType == .digit
        }
    }

    /// L20 `cover_common(x)`: từ trái sang, mỗi bước lấy đoạn **dài nhất** (6 … 2 chữ) có nghĩa đầu VP viết thường, không
    /// có ⇒ không phủ được (không thử lại cách cắt khác); cần ≥ 2 đoạn.
    private func isCoveredByCommonWords(_ word: Word) -> Bool {
        var start = 0
        var parts = 0
        while start < word.count {
            var hit = 0
            var end = min(word.count, start + Rules.commonPhraseMaxPart)
            while end >= start + 2 {
                if dictionaries.status(word: word.slice(start, end)) == .common {
                    hit = end
                    break
                }
                end -= 1
            }
            if hit == 0 { return false }
            parts += 1
            start = hit
        }
        return parts >= Rules.commonPhraseMinParts
    }

    /// L22 `verb_head(r)`. LAC chưa từng gắn nhãn thực thể cho phần trước đuôi ⇔ không có trong `counts.entities` ⇒ tổng
    /// số nhãn của nó = `counts.others`.
    private func isVerbHead(_ row: Row) -> Bool {
        guard row.isRuleRow, row.category == .place || row.category == .organization,
              let suffixLength = row.ruleSuffixLength, row.count < Rules.verbHeadMaxCount else { return false }
        let head = row.word.dropLast(suffixLength)
        guard head.count >= 2, dictionaries.status(word: head) == .common, counts.entities[head] == nil else { return false }
        let total = Int(counts.others[head] ?? 0)
        guard total >= Rules.verbHeadMinTagged else { return false }
        return Double(counts.verbish[head] ?? 0) >= Rules.verbHeadVerbishRatio * Double(total)
    }

    /// L21 `name_fragment`: `base = w[:-1]`.
    private func isNameFragment(_ row: Row) -> Bool {
        let word = row.word
        guard row.category == .person, word.count >= 3 else { return false }
        let base = word.dropLast(1)
        guard categories[base] == .person, let baseCount = rowCounts[base], baseCount >= Rules.nameFragmentBaseMinCount,
              Double(row.count) < Rules.nameFragmentRatio * Double(baseCount) else { return false }
        return !setup.isPersonSuffix(word.suffix(1)) && !setup.isPersonSuffix(word.suffix(2))
    }

    /// L25 `len(w) >= 3 and w.startswith(QUANT_HEAD)`.
    private static func hasQuantityHead(_ word: Word) -> Bool {
        guard word.count >= Rules.quantityHeadMinLength else { return false }
        return Rules.quantityHeads.contains { head in
            head.count <= word.count && word.slice(0, head.count) == head
        }
    }

    /// L24 `title_fragment(r)`: `(w[-1] + c) in PERSON_SUFFIXES or (w[-2:] + c) in PERSON_SUFFIXES`.
    private func isTitleFragment(_ row: Row) -> Bool {
        let word = row.word
        guard row.category == .person, word.count >= 2, let longer = extensions[word] else { return false }
        let lastOne = word.suffix(1).scalars
        let lastTwo = word.suffix(2).scalars
        for (last, count) in longer where Double(count) >= Rules.titleFragmentRatio * Double(row.count) {
            if setup.isPersonSuffix(Word(scalars: lastOne + [last])) || setup.isPersonSuffix(Word(scalars: lastTwo + [last])) {
                return true
            }
        }
        return false
    }
}
