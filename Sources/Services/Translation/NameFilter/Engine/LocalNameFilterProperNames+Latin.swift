import Foundation

/// Tên kiểu Latin có tiền tố / hậu tố (2026-11-28, anh Bửu: "bài trừ tiền tố hậu tố lấy phần còn lại") — `latin_affixed`
/// của `Docs/Plans/local-name-filter-lac/name_meaning.py` và `latin_core` của `lacpipe.py` (luật phân loại L16).
extension LocalNameFilterProperNames {
    /// Dấu tách các nghĩa của một mục từ điển khi xét lõi Latin (`R.readings` của `local_name_filter2.py`: `/` `|` `;`).
    private static let readingSeparators: Set<Character> = ["/", "|", ";"]

    /// `latin_affixed`: bỏ tiền tố ở đầu (danh sách "Tiền tố", **mọi** loại) và / hoặc hậu tố ở cuối (**mọi** mục của danh
    /// sách "Hậu tố", kể cả Nhân danh), dài nhất trước, ít nhất một phía; phần lõi ≥ 2 chữ ra tên Latin (`latinCore(of:)`)
    /// **và** khác âm Hán-Việt của lõi ⇒ "nghĩa tiền tố + Latin + nghĩa hậu tố" theo vị trí từng mục (trước / sau; tiền tố
    /// xếp trước hậu tố khi cùng phía): 古赫密斯语 ⇒ "cổ Hermes ngữ", 霍伊河 ⇒ "Khoy hà" (bật Latin), 图铎家族 ⇒ "Tudor gia tộc"
    /// (图铎 = Tudor trong Name). Nghĩa mục lấy nguyên chữ người dùng viết. Có dấu ngăn tên (`·` `.` `•`) hoặc không ra ⇒
    /// `nil`.
    func latinAffixed(_ word: Word) -> Proper? {
        guard !word.scalars.contains(where: { Self.separators.contains($0) }) else { return nil }
        let prefixLengths = Self.matchingLengths(max: min(prefixMaxLength, word.count - 2)) {
            prefixes[word.slice(0, $0)] != nil
        }
        let affixLengths = Self.matchingLengths(max: min(affixMaxLength, word.count - 2)) {
            affixes[word.suffix($0)] != nil
        }
        for prefixLength in prefixLengths {
            for affixLength in affixLengths {
                guard prefixLength + affixLength > 0, word.count - prefixLength - affixLength >= 2 else { continue }
                let core = word.slice(prefixLength, word.count - affixLength)
                guard let latin = latinCore(of: core),
                      latin.text.lowercased() != reading(core, surnameLength: 0).lowercased() else { continue }
                var front: [String] = []
                var back: [String] = []
                let entries = [
                    prefixLength > 0 ? prefixes[word.slice(0, prefixLength)] : nil,
                    affixLength > 0 ? affixes[word.suffix(affixLength)] : nil
                ]
                for entry in entries.compactMap({ $0 }) {
                    if entry.position == .before { front.append(entry.meaning) } else { back.append(entry.meaning) }
                }
                return Proper(text: (front + [latin.text] + back).joined(separator: " "), isGuessed: latin.isGuessed)
            }
        }
        return nil
    }

    /// `latin_core_of` (2026-11-28, anh Bửu duyệt): tên Latin của **lõi** một tên kiểu Latin (chỉ `latinAffixed` gọi —
    /// tiền tố của mảnh tên `prefixed` vẫn dùng `latinName(of:)` như `latin_of` của Python):
    /// - (a) lõi khớp trọn một mục **Name** (riêng → Chung → gốc trừ đã xoá) hoặc **VP riêng của truyện**
    ///   (`LocalNameFilterDictionaries.trustedValue`) mà nghĩa chọn bằng `pick` là chữ Latin ⇒ nhận luôn, **không** xét
    ///   chữ phiên âm (图铎 = Tudor — tập 268 chữ thiếu 图 铎). Nghĩa đó không phải chữ Latin ⇒ đi tiếp như dưới;
    /// - như `latinName(of:)`: cả lõi / phủ trọn bằng `coverEntry` (VP Chung / gốc vẫn qua chốt chữ phiên âm) mà nghĩa là
    ///   chữ Latin; không có trong từ điển ⇒ mô hình đoán khi bật Latin và **mọi** chữ là chữ phiên âm — bật "Nới đoán tên
    ///   Latin" (`loosensLatinCore`, hướng b) thì chỉ cần ≥ một nửa (`looksTransliterated`).
    /// "Khác âm Hán-Việt" do `latinAffixed` xét. Không ra Latin ⇒ `nil`.
    func latinCore(of core: Word) -> Proper? {
        if let raw = dictionaries.trustedValue(core.string) {
            let picked = pick(raw, key: core)
            if Self.isLatinName(picked) { return Proper(text: picked, isGuessed: false) }
        }
        if let found = coverEntryOrCover(core) {
            return Self.isLatinName(found) ? Proper(text: found, isGuessed: false) : nil
        }
        guard let latinModel, !translitChars.isEmpty else { return nil }
        let transliterated = loosensLatinCore
            ? looksTransliterated(core)
            : core.scalars.allSatisfy { translitChars.contains($0) }
        guard transliterated, let guess = latinModel.predict(core.scalars) else { return nil }
        return Proper(text: guess, isGuessed: true)
    }

    /// `latin_core` (luật phân loại L16): `head` (name đã bỏ hậu tố dò), hoặc `head` bỏ một tiền tố của danh sách (mọi
    /// loại, dài nhất trước, phần còn ≥ 2 chữ), có trong từ điển (`dictionaryValue` — Name rồi VP) với **ít nhất một**
    /// nghĩa (tách `/` `|` `;`, không qua `pick`) là chữ Latin khác âm Hán-Việt của lõi, và lõi có ≥ 1 chữ phiên âm
    /// (霍伊 = "Hoắc Y/Khoy"). Không theo công tắc "Ưu tiên tên Latin".
    func hasLatinCore(_ head: Word) -> Bool {
        var cores = [head]
        let longest = min(prefixMaxLength, head.count - 2)
        if longest >= 1 {
            for length in stride(from: longest, through: 1, by: -1) where prefixes[head.slice(0, length)] != nil {
                cores.append(head.slice(length, head.count))
            }
        }
        for core in cores {
            guard core.count >= 2, hasTranslitChar(core), let raw = dictionaries.dictionaryValue(core.string) else { continue }
            let hanViet = reading(core, surnameLength: 0).lowercased()
            let readings = raw.split(whereSeparator: { Self.readingSeparators.contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if readings.contains(where: { Self.isLatinName($0) && $0.lowercased() != hanViet }) { return true }
        }
        return false
    }

    /// Các độ dài `max … 1` thoả `matches`, rồi 0 (không bỏ gì ở phía đó) — thứ tự thử của `latin_affixed`.
    private static func matchingLengths(max longest: Int, _ matches: (Int) -> Bool) -> [Int] {
        var lengths: [Int] = []
        if longest >= 1 {
            for length in stride(from: longest, through: 1, by: -1) where matches(length) { lengths.append(length) }
        }
        lengths.append(0)
        return lengths
    }
}
