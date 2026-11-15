import Foundation

/// Cắt một từ **romaji** thành âm tiết rồi sinh thẳng phiên âm cho VieNeu (1.3.950) — lõi của `VieNeuJapaneseNameReader`.
///
/// ## Vì sao sinh thẳng phiên âm, không viết ra chính tả Việt
/// Bảng `JapaneseTransliterator.romajiToViSyllable` (dùng chung với NghiTTS) ra chữ như "kô", "gi", "ic ki", "hôc"; đưa
/// qua `SeaG2P` thì nhiều chữ bị đọc sai ("gi" mất nguyên âm, "ic" thành `ˈaɪk`, "hôc" thành `hˈo sˈe`) và hàng y ra
/// "da / du / dô" = âm /z/. Phiên âm ở đây đi **nguyên văn** qua `SeaG2P` (`SeaG2P.rawPhonemeOpen` / `Close`).
///
/// ## Luật đọc — anh Bửu nghe và duyệt từng nhóm (mẫu C / E / F cách A, 2026-11-15)
/// - Âm tiết thường = phụ âm đầu + `ˈ` + nguyên âm, đúng dạng âm tiết Việt thanh ngang (`sˈaː sˈu kˈe`).
/// - `shi` → `sˈi`, `ji` → `zˈi`, `tsu` → `sˈu` (không dùng cụm `ts`); hàng y dùng `j` (`jˈu kˈi`).
/// - Âm ghép: `kya` → `kˈiə`, `kyu` → `kˈiw`, `kyo` → `kˈi ˈo` (hai âm tiết) — không dùng cụm `kj` / `ɹj` (Nano đọc không ra).
/// - `n` cuối âm tiết → đuôi `n`; `m` trước b / p → đuôi `m`; `ai / oi / ui` → bán nguyên âm cuối `j`.
/// - Âm ngắt (phụ âm kép) → âm tiết trước mang `ɜ` + phụ âm cuối (`hˈaːɜt̪ t̪ˈo ɹˈi`).
/// - Trường âm (`ou`, `uu`, `oo`, `ei`, `ii`, `aa`, `ee`, `oh` cuối âm tiết) gộp về âm ngắn; `oue` giữ `u` ("Inoue").
///
/// **Bản chép Python** của `normalize` + `syllables` + `phonemes` nằm ở `Scripts/gen_vieneu_romaji_english_lookalikes.py`
/// (sinh danh sách loại trừ, có `--selftest` đối chiếu với các chuỗi đã duyệt). Sửa luật ở đây thì sửa cả bên đó.
enum VieNeuRomajiSyllabifier {
    struct Syllable {
        var onset: String
        var vowel: Character
        /// Phiên âm của phụ âm cuối (`n`, `m`, hoặc âm tắc của âm ngắt); rỗng = âm tiết mở.
        var coda = ""
        var isGeminate = false
        var hasGlide = false
    }

    private static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]
    private static let plainOnsets: Set<Character> = ["k", "s", "t", "n", "h", "m", "r", "g", "z", "d", "b", "p"]
    /// Nguyên âm đi được sau âm ghép / "y" (a, u, o), sau "sh" / "ch" / "j" (a, i, u, o) và sau "w" (a, i, e, o).
    private static let backVowels: Set<Character> = ["a", "u", "o"]
    private static let sibilantVowels: Set<Character> = ["a", "i", "u", "o"]
    private static let wVowels: Set<Character> = ["a", "i", "e", "o"]
    private static let palatalOnsets: Set<String> = ["ky", "gy", "ny", "hy", "my", "ry", "by", "py"]
    private static let geminateCoda: [Character: String] = ["k": "k", "t": "t̪", "p": "p", "s": "t̪"]
    private static let onsetPhone: [String: String] = [
        "": "", "k": "k", "s": "s", "t": "t̪", "n": "n", "h": "h", "m": "m", "r": "ɹ", "g": "ɣ", "z": "z",
        "d": "ɗ", "b": "b", "p": "p", "w": "w", "y": "j", "j": "z", "f": "f", "sh": "s", "ch": "tʃ", "ts": "s",
        "ky": "k", "gy": "ɣ", "ny": "n", "hy": "h", "my": "m", "ry": "ɹ", "by": "b", "py": "p"
    ]
    private static let vowelPhone: [Character: String] = ["a": "aː", "i": "i", "u": "u", "e": "e", "o": "o"]
    /// Cặp trường âm gộp về âm ngắn, đúng thứ tự áp trong `normalize` ("ou" xử lý riêng vì còn luật "oue").
    private static let longVowelPairs: [(first: Character, second: Character, short: Character)] = [
        ("a", "a", "a"), ("i", "i", "i"), ("u", "u", "u"), ("e", "e", "e"), ("o", "o", "o"), ("e", "i", "e")
    ]

    // MARK: - Gộp trường âm

    /// `key`: chữ thường ASCII, có thể còn dấu nháy sau "n" ("jun'ichi").
    static func normalize(_ key: String) -> [Character] {
        var word = replacingPair(Array(key), "o", "h", with: "o", unlessFollowedBy: ["a", "i", "u", "e", "o", "y"])
        var previous: [Character] = []
        while word != previous {
            previous = word
            word = replacingPair(word, "o", "u", with: "o", unlessFollowedBy: ["e"])
            for pair in longVowelPairs {
                word = replacingPair(word, pair.first, pair.second, with: pair.short, unlessFollowedBy: [])
            }
        }
        return word
    }

    /// Thay mọi cặp `first second` (quét trái sang phải, không chồng lấn) bằng `replacement`, trừ khi ngay sau cặp là một
    /// ký tự trong `blockers`.
    private static func replacingPair(
        _ word: [Character],
        _ first: Character,
        _ second: Character,
        with replacement: Character,
        unlessFollowedBy blockers: Set<Character>
    ) -> [Character] {
        var result: [Character] = []
        result.reserveCapacity(word.count)
        var index = 0
        while index < word.count {
            if word[index] == first, index + 1 < word.count, word[index + 1] == second,
               !(index + 2 < word.count && blockers.contains(word[index + 2])) {
                result.append(replacement)
                index += 2
            } else {
                result.append(word[index])
                index += 1
            }
        }
        return result
    }

    // MARK: - Cắt âm tiết

    /// Cắt được **hết** thành ít nhất hai âm tiết ⇒ danh sách âm tiết; còn lại ⇒ `nil` (không phải romaji).
    static func syllables(of key: String) -> [Syllable]? {
        let word = normalize(key)
        var syllables: [Syllable] = []
        var index = 0
        while index < word.count {
            let char = word[index]
            let next: Character? = index + 1 < word.count ? word[index + 1] : nil
            // "n" mũi cuối âm tiết: không đứng trước nguyên âm / y, hoặc có dấu nháy theo sau.
            if char == "n", isMoraicNasal(before: next) {
                guard let last = syllables.last, last.coda.isEmpty else { return nil }
                syllables[syllables.count - 1].coda = "n"
                index += next == "'" ? 2 : 1
                continue
            }
            if char == "m", next == "b" || next == "p" {
                guard let last = syllables.last, last.coda.isEmpty else { return nil }
                syllables[syllables.count - 1].coda = "m"
                index += 1
                continue
            }
            // Âm ngắt: phụ âm kép, và "tch".
            var geminate: Character?
            if geminateCoda[char] != nil, next == char {
                geminate = char
            } else if char == "t", next == "c", index + 2 < word.count, word[index + 2] == "h" {
                geminate = "t"
            }
            if let geminate, let stop = geminateCoda[geminate] {
                guard let last = syllables.last, last.coda.isEmpty else { return nil }
                syllables[syllables.count - 1].coda = stop
                syllables[syllables.count - 1].isGeminate = true
                index += 1
                continue
            }
            guard let (onset, vowel) = splitSyllable(word, at: index) else { return nil }
            syllables.append(Syllable(onset: onset, vowel: vowel))
            index += onset.count + 1
        }
        guard syllables.count >= 2 else { return nil }
        return mergingGlides(syllables)
    }

    /// "n" là âm mũi cuối âm tiết khi sau nó không phải nguyên âm / "y" (hoặc là dấu nháy, hoặc hết từ).
    private static func isMoraicNasal(before next: Character?) -> Bool {
        guard let next else { return true }
        return !(vowels.contains(next) || next == "y")
    }

    private static func splitSyllable(_ word: [Character], at index: Int) -> (String, Character)? {
        if index + 2 < word.count {
            let two = String(word[index...index + 1])
            let vowel = word[index + 2]
            if palatalOnsets.contains(two), backVowels.contains(vowel) { return (two, vowel) }
            if two == "sh" || two == "ch", sibilantVowels.contains(vowel) { return (two, vowel) }
            if two == "ts", vowel == "u" { return (two, vowel) }
        }
        let char = word[index]
        if vowels.contains(char) { return ("", char) }
        guard index + 1 < word.count else { return nil }
        let vowel = word[index + 1]
        if plainOnsets.contains(char), vowels.contains(vowel) { return (String(char), vowel) }
        if char == "y", backVowels.contains(vowel) { return ("y", vowel) }
        if char == "w", wVowels.contains(vowel) { return ("w", vowel) }
        if char == "j", sibilantVowels.contains(vowel) { return ("j", vowel) }
        if char == "f", vowel == "u" { return ("f", vowel) }
        return nil
    }

    /// "ai / oi / ui" đọc thành **một** âm tiết có bán nguyên âm cuối (`kai` → `kˈaːj`), trừ khi "i" còn mang đuôi n.
    private static func mergingGlides(_ syllables: [Syllable]) -> [Syllable]? {
        var merged: [Syllable] = []
        for syllable in syllables {
            if let previous = merged.last,
               syllable.onset.isEmpty, syllable.vowel == "i", syllable.coda.isEmpty,
               previous.coda.isEmpty, !previous.hasGlide,
               backVowels.contains(previous.vowel),
               !palatalOnsets.contains(previous.onset) {
                merged[merged.count - 1].hasGlide = true
                continue
            }
            merged.append(syllable)
        }
        return merged.count >= 2 ? merged : nil
    }

    // MARK: - Phiên âm

    /// Mỗi phần tử là phiên âm của **một** âm tiết đọc (âm ghép `kyo` cho hai phần tử).
    static func phonemes(of syllables: [Syllable]) -> [String] {
        var parts: [String] = []
        for syllable in syllables {
            let onset = onsetPhone[syllable.onset] ?? ""
            var tail = syllable.hasGlide ? "j" : ""
            tail += syllable.isGeminate ? "ɜ" + syllable.coda : syllable.coda
            if palatalOnsets.contains(syllable.onset) {
                switch syllable.vowel {
                case "a": parts.append(onset + "ˈiə" + tail)
                case "u": parts.append(onset + "ˈiw" + tail)
                default:
                    parts.append(onset + "ˈi")
                    parts.append("ˈo" + tail)
                }
            } else {
                parts.append(onset + "ˈ" + (vowelPhone[syllable.vowel] ?? "") + tail)
            }
        }
        return parts
    }
}
