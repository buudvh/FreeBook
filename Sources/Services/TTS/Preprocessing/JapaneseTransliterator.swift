import Foundation

final class JapaneseTransliterator {
    private static let kanaToRomaji: [String: String] = [
        // Hiragana cơ bản
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "を": "o", "ん": "n",

        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",

        // Katakana cơ bản
        "ア": "a", "イ": "i", "ウ": "u", "エ": "e", "オ": "o",
        "カ": "ka", "キ": "ki", "ク": "ku", "ケ": "ke", "コ": "ko",
        "サ": "sa", "シ": "shi", "ス": "su", "セ": "se", "ソ": "so",
        "タ": "ta", "チ": "chi", "ツ": "tsu", "テ": "te", "ト": "to",
        "ナ": "na", "ニ": "ni", "ヌ": "nu", "ネ": "ne", "ノ": "no",
        "ハ": "ha", "ヒ": "hi", "フ": "fu", "ヘ": "he", "ホ": "ho",
        "マ": "ma", "ミ": "mi", "ム": "mu", "メ": "me", "モ": "mo",
        "ヤ": "ya", "ユ": "yu", "ヨ": "yo",
        "ラ": "ra", "リ": "ri", "ル": "ru", "レ": "re", "ロ": "ro",
        "ワ": "wa", "ヲ": "o", "ン": "n",

        "ガ": "ga", "ギ": "gi", "グ": "gu", "ゲ": "ge", "ゴ": "go",
        "ザ": "za", "ジ": "ji", "ズ": "zu", "ゼ": "ze", "ゾ": "zo",
        "ダ": "da", "ヂ": "ji", "ヅ": "zu", "デ": "de", "ド": "do",
        "バ": "ba", "ビ": "bi", "ブ": "bu", "ベ": "be", "ボ": "bo",
        "パ": "pa", "ピ": "pi", "プ": "pu", "ペ": "pe", "ポ": "po",

        // Âm ghép Hiragana (Yo-on)
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",

        // Âm ghép Katakana (Yo-on)
        "キャ": "kya", "キュ": "kyu", "キョ": "kyo",
        "シャ": "sha", "シュ": "shu", "ショ": "sho",
        "チャ": "cha", "チュ": "chu", "チョ": "cho",
        "ニャ": "nya", "ニュ": "nyu", "ニョ": "nyo",
        "ヒャ": "hya", "ヒュ": "hyu", "ヒョ": "hyo",
        "ミャ": "mya", "ミュ": "myu", "ミョ": "myo",
        "リャ": "rya", "リュ": "ryu", "リョ": "ryo",
        "ギャ": "gya", "ギュ": "gyu", "ギョ": "gyo",
        "ジャ": "ja", "ジュ": "ju", "ジョ": "jo",
        "ビャ": "bya", "ビュ": "byu", "ビョ": "byo",
        "ピャ": "pya", "ピュ": "pyu", "ピョ": "pyo",

        // Âm ngoại lai của katakana hiện đại. Thiếu nhóm này thì ký tự lạ được giữ nguyên và trôi
        // xuống pipeline tiếng Anh, ra chuỗi vô nghĩa.
        "ヴ": "vu", "ヴァ": "va", "ヴィ": "vi", "ヴェ": "ve", "ヴォ": "vo",
        "ファ": "fa", "フィ": "fi", "フェ": "fe", "フォ": "fo",
        "ティ": "ti", "ディ": "di", "トゥ": "tu", "ドゥ": "du",
        "ウィ": "wi", "ウェ": "we", "ウォ": "wo",
        "ジェ": "je", "シェ": "she", "チェ": "che",

        // Ký tự trường âm bị **bỏ**, tức âm dài viết như âm ngắn ("ラーメン" → "ramen"). Đây là lựa
        // chọn nghe, không phải chuẩn Hepburn: tiếng Việt không có nguyên âm dài, nên nhân đôi nguyên
        // âm (bản 1.3.290) làm espeak-vi/Piper đọc thành **hai âm tiết rời** có ngắt thanh hầu ở giữa,
        // nghe như nói lắp. Đừng "sửa lại cho đúng sách" mà không nghe thử.
        "ー": ""
    ]

    static func convertToRomaji(_ text: String) -> String {
        let chars = Array(text)
        var result = ""
        var i = 0

        while i < chars.count {
            // Kiểm tra âm ghép Yo-on (2 ký tự)
            if i < chars.count - 1 {
                let digraph = String(chars[i...i+1])
                if let romaji = kanaToRomaji[digraph] {
                    result += romaji
                    i += 2
                    continue
                }
            }

            let charStr = String(chars[i])

            // Kiểm tra âm ngắt Sokuon (っ/ッ)
            if charStr == "っ" || charStr == "ッ" {
                if i < chars.count - 1 {
                    let nextCharStr = String(chars[i+1])
                    if let nextRomaji = kanaToRomaji[nextCharStr], let firstLetter = nextRomaji.first {
                        // Nhân đôi phụ âm đứng trước (trừ nguyên âm)
                        if !"aeiou".contains(firstLetter) {
                            result += String(firstLetter)
                        }
                    }
                }
                i += 1
                continue
            }

            if let romaji = kanaToRomaji[charStr] {
                result += romaji
            } else {
                result += charStr
            }
            i += 1
        }
        return result
    }

    // Bảng ánh xạ Romaji sang Phiên âm Việt
    private static let romajiToViSyllable: [String: String] = [
        "sha": "sa", "shi": "si", "shu": "su", "she": "sê", "sho": "sô",
        "cha": "cha", "chi": "chi", "chu": "chu", "che": "chê", "cho": "chô",
        "tsu": "chư",
        "kya": "kia", "kyu": "kiu", "kyo": "kiô",
        "nya": "nia", "nyu": "niu", "nyo": "niô",
        "hya": "hia", "hyu": "hiu", "hyo": "hiô",
        "mya": "mia", "myu": "miu", "myo": "miô",
        "rya": "ria", "ryu": "riu", "ryo": "riô",
        "gya": "ghia", "gyu": "ghiu", "gyo": "ghiô",
        "bya": "bia", "byu": "biu", "byo": "biô",
        "pya": "pia", "pyu": "piu", "pyo": "piô",
        "ka": "ka", "ki": "ki", "ku": "kư", "ke": "kê", "ko": "kô",
        "sa": "xa", "si": "xi", "su": "xư", "se": "xê", "so": "xô",
        "ta": "ta", "ti": "chi", "tu": "chư", "te": "tê", "to": "tô",
        "na": "na", "ni": "ni", "nu": "nư", "ne": "nê", "no": "nô",
        "ha": "ha", "hi": "hi", "hu": "hư", "he": "hê", "ho": "hô",
        "fu": "phư",
        "ma": "ma", "mi": "mi", "mu": "mư", "me": "mê", "mo": "mô",
        // ya/yu/yo là /ja ju jo/, và tiếng Việt **không có** chữ nào đọc đúng /j/ ở vị trí phụ âm đầu,
        // nên đây là chọn cái sai ít hơn. Bản 1.3.290 viết bằng bán nguyên âm "i" với lý do "d" đọc
        // /z/ ở giọng Bắc; nhưng espeak-vi đọc "ia" là **nguyên âm đôi** /iə/ chứ không phải glide, nên
        // "Yamato" ra "i-a-ma-tô" — sai cả số âm tiết, tệ hơn sai một phụ âm. Quay lại "d" theo yêu cầu
        // người dùng (và "d" đọc đúng /j/ ở giọng Nam). Hệ quả biết trước: hàng này trùng đầu ra với
        // hàng za/zi/zu/ze/zo. Hàng yo-on (kya, ryu, gyo…) **giữ** chữ "i" vì ở đó "i" là dấu ngạc hoá
        // bên trong âm tiết, không phải phụ âm đầu.
        "ya": "da", "yi": "di", "yu": "du", "ye": "dê", "yo": "dô",
        "ra": "ra", "ri": "ri", "ru": "rư", "re": "rê", "ro": "rô",
        "wa": "oa", "wi": "uy", "we": "uê", "wo": "ô",
        "ga": "ga", "gi": "ghi", "gu": "gư", "ge": "ghê", "go": "gô",
        "za": "da", "zi": "di", "zu": "dư", "ze": "dê", "zo": "dô",
        "da": "đa", "di": "đi", "du": "đư", "de": "đê", "do": "đô",
        "ba": "ba", "bi": "bi", "bu": "bư", "be": "bê", "bo": "bô",
        "pa": "pa", "pi": "pi", "pu": "pư", "pe": "pê", "po": "pô",
        "ja": "gia", "ji": "gi", "ju": "giu", "je": "giê", "jo": "giô",
        "a": "a", "i": "i", "u": "ư", "e": "ê", "o": "ô",
        // Trường âm **không** khai khoá ở đây — xem `collapseLongVowels`. Gộp phải làm *trước* khi cắt
        // âm tiết: `greedySegment` khớp dài nhất **tại từng vị trí**, nên ở "arigatou" nó ăn "to" ở vị
        // trí 5 rồi bỏ lại "u" thành một âm tiết "ư" thừa — khoá "ou" trong bảng này không bao giờ có cơ
        // hội khớp. Bản 1.3.291 thêm "ou"/"ei" vào đây và tưởng đã xong, nhưng "arigatou" vẫn ra
        // "a-ri-ga-tô-ư" và "ryuu" ra "riu-ư".
        // Âm ngoại lai của katakana hiện đại: ヴ và hàng ファ/フィ/フェ/フォ. Các âm khác (ティ, ジェ,
        // シェ, チェ) đã có khoá trong bảng gốc nên không khai lại — trùng khoá trong dictionary
        // literal làm crash lúc chạy.
        "va": "va", "vi": "vi", "vu": "vu", "ve": "vê", "vo": "vô",
        "fa": "pha", "fi": "phi", "fe": "phê", "fo": "phô",
        "n": "n"
    ]

    private static let validRomajiSyllables: Set<String> = Set(romajiToViSyllable.keys)

    /// Các cách viết trường âm trong romaji, gộp về âm ngắn. `ai/oi/ui/au` **không** có ở đây: đó là
    /// nguyên âm đôi thật, gộp là mất âm ("senpai", "kaze").
    private static let longVowelForms: [(String, String)] = [
        ("ou", "o"), ("ei", "e"), ("aa", "a"), ("ii", "i"), ("uu", "u"), ("ee", "e"), ("oo", "o")
    ]

    /// Đọc trường âm **như âm ngắn**: "arigatou" → "arigato", "ryuu" → "ryu", "sensei" → "sense",
    /// "shoujo" → "shojo". Cùng lựa chọn với `ー` ở bảng kana — tiếng Việt không có nguyên âm dài, và
    /// nhân đôi nguyên âm làm espeak-vi/Piper đọc thành hai âm tiết rời nghe như nói lắp.
    ///
    /// Lặp tới khi ổn định vì một lượt thay có thể sinh ra cặp mới ("aaa" → "aa" → "a").
    private static func collapseLongVowels(_ word: String) -> String {
        var current = word
        var previous = ""
        while current != previous {
            previous = current
            for (long, short) in longVowelForms {
                current = current.replacingOccurrences(of: long, with: short)
            }
        }
        return current
    }

    private static func normalizeRomaji(_ word: String) -> String {
        var w = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let macronMap = ["ā": "a", "ī": "i", "ū": "u", "ē": "e", "ō": "o"]
        for (k, v) in macronMap {
            w = w.replacingOccurrences(of: k, with: v)
        }
        w = w.folding(options: .diacriticInsensitive, locale: nil)
        return collapseLongVowels(w)
    }

    private static func greedySegment(_ word: String) -> [String]? {
        var syllables: [String] = []
        let chars = Array(word)
        var i = 0
        while i < chars.count {
            var matched = false
            for len in [3, 2, 1] {
                if i + len <= chars.count {
                    let candidate = String(chars[i..<i+len])
                    if validRomajiSyllables.contains(candidate) {
                        if candidate == "n" && len == 1 {
                            if i + 1 < chars.count {
                                let nextChar = chars[i+1]
                                if "aiueony".contains(nextChar) {
                                    continue
                                }
                            }
                        }
                        syllables.append(candidate)
                        i += len
                        matched = true
                        break
                    }
                }
            }
            if !matched {
                return nil
            }
        }
        return syllables
    }

    static func isJapaneseRomaji(_ word: String) -> Bool {
        // Quyết định thuộc `ForeignScriptClassifier`: bản cũ ở đây coi mọi chuỗi cắt được thành âm
        // romaji là tiếng Nhật rồi chống đỡ bằng `englishBlacklist` ~420 từ vá theo từng ca — tập từ
        // tiếng Anh cần loại trừ là vô hạn nên cách đó không bao giờ đúng được.
        ForeignScriptClassifier.isJapaneseRomaji(word)
    }

    static func transliterateRomaji(_ word: String) -> String {
        let normalized = normalizeRomaji(word)

        var sokuonChars: [(Int, Character)] = []
        var simplifiedChars: [Character] = []
        let chars = Array(normalized)
        var i = 0
        while i < chars.count {
            if i < chars.count - 1 && chars[i] == chars[i+1] && !"aeiou".contains(chars[i]) {
                sokuonChars.append((simplifiedChars.count, chars[i]))
                simplifiedChars.append(chars[i])
                i += 2
            } else {
                simplifiedChars.append(chars[i])
                i += 1
            }
        }
        let simplified = String(simplifiedChars)

        guard let syllables = greedySegment(simplified) else {
            return word
        }

        let viSyllables = syllables.map { romajiToViSyllable[$0] ?? $0 }

        // Nhập âm tiết vào âm tiết trước, và ghi lại âm tiết romaji thứ `i` rơi vào ô nào của `merged`
        // — bước gắn sokuon phía dưới cần đúng ánh xạ đó. Bản cũ tính lại bằng `findMergedIndex`, chỉ
        // biết luật `"n"`; nay có hai luật nhập nên tính một lần ở đây là nguồn duy nhất.
        var merged: [String] = []
        var mergedIndexOfSyllable = [Int](repeating: 0, count: viSyllables.count)
        for (index, syllable) in viSyllables.enumerated() {
            if syllable == "n", index > 0, !merged.isEmpty {
                merged[merged.count - 1] += "n"
            } else if syllable == "i", index > 0, let previous = merged.last, canTakeGlideI(previous) {
                merged[merged.count - 1] += "i"
            } else {
                merged.append(syllable)
            }
            mergedIndexOfSyllable[index] = merged.count - 1
        }

        if !sokuonChars.isEmpty {
            var pos = 0
            var sylBoundaries: [(Int, Int)] = []
            for syl in syllables {
                sylBoundaries.append((pos, pos + syl.count))
                pos += syl.count
            }

            for (sokuPos, sokuChar) in sokuonChars {
                for (si, (start, end)) in sylBoundaries.enumerated() {
                    if sokuPos >= start && sokuPos < end {
                        let mergedIdx = mergedIndexOfSyllable[si]
                        if mergedIdx > 0 && mergedIdx < merged.count {
                            let sokuVi = sokuonCoda(sokuChar)
                            merged[mergedIdx - 1] = merged[mergedIdx - 1] + sokuVi
                        }
                        break
                    }
                }
            }
        }

        // Không bao giờ trả rỗng: một token biến thành "" là **mất chữ** khi đọc, và pipeline chỉ có
        // chốt chống rỗng ở mức cả chunk (`PiperTTSService.isUnspeakable`), không có chốt mức token.
        let result = merged.joined(separator: "-")
        return result.isEmpty ? word : result
    }

    /// `i` đi sau một nguyên âm khác là **bán nguyên âm cuối**, tiếng Việt viết liền thành một rime:
    /// "senpai" → `xên-pai`, "koi" → `kôi`, "sui" → `xưi`. Đọc rời thành hai âm tiết (`pa-i`) là sai.
    ///
    /// Chỉ nhập được vào âm tiết kết thúc bằng nguyên âm **khác** `i`/`y`: nhập vào âm tiết đã có phụ âm
    /// cuối (`xên`) hoặc đã kết thúc bằng bán nguyên âm (`uy`) là tạo rime không tồn tại.
    private static func canTakeGlideI(_ syllable: String) -> Bool {
        guard let last = syllable.last else { return false }
        return "aăâeêoôơuư".contains(last)
    }

    private static func sokuonCoda(_ char: Character) -> String {
        let mapping: [Character: String] = [
            "k": "c", "s": "t", "t": "t", "p": "p",
            "g": "c", "b": "p", "d": "t", "z": "t",
            "n": "n", "m": "m"
        ]
        if let mapped = mapping[char] {
            return mapped
        }
        return String(char)
    }
}

// MARK: - Vietnamese Number Speller
