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

        // Ký tự trường âm
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
        "n": "n"
    ]

    private static let validRomajiSyllables: Set<String> = Set(romajiToViSyllable.keys)

    private static let englishBlacklist: Set<String> = [
        "no", "so", "to", "do", "go", "on", "an", "in", "he", "she", "we", "me",
        "be", "re", "or", "by", "my", "if", "up", "at", "it", "is", "as", "am",
        "one", "two", "ten", "run", "ran", "son", "sun", "won", "ton", "gun", "fun",
        "pan", "pin", "sin", "win", "bin", "ban", "can", "man", "fan", "van", "dan",
        "age", "ago", "are", "ate", "ape", "use", "ore", "owe", "awe",
        "sea", "see", "tea", "tee", "bee", "fee", "pea",
        "too", "woo", "boo", "goo", "moo", "zoo",
        "pie", "tie", "die", "lie", "vie",
        "sue", "due", "hue", "rue", "cue",
        "you", "our", "her", "him", "his", "who",
        "take", "make", "sake", "wake", "bake", "cake", "fake", "lake", "rake",
        "name", "same", "came", "game", "fame", "dame", "tame", "lame",
        "some", "come", "home", "done", "gone", "bone", "tone", "zone", "none",
        "more", "bore", "core", "fore", "gore", "pore", "sore", "wore", "tore",
        "page", "sage", "cage", "rage", "wage",
        "nose", "rose", "pose", "dose", "hose",
        "side", "wide", "hide", "ride", "tide",
        "time", "dime", "mime", "lime",
        "mine", "wine", "dine", "fine", "line", "nine", "pine", "vine",
        "sure", "pure", "cure",
        "pipe", "ripe", "wipe",
        "pike", "hike", "bike", "mike",
        "note", "vote", "dote",
        "open", "oven",
        "upon",
        "reason", "season", "poison", "prison", "bison",
        "position", "opinion", "pension", "tension", "session", "mission",
        "passion", "fashion", "nation", "station", "motion", "notion",
        "opposite", "sunshine", "someone", "anyone",
        "imagine", "machine", "routine", "marine", "genuine",
        "revenue", "continue", "pursue", "issue",
        "orange", "manage", "passage", "message", "damage", "garage",
        "surprise", "paradise", "enterprise",
        "noise", "poise", "raise",
        "piano", "casino", "volcano",
        "refuse", "rescue", "statue",
        "tongue", "unique", "technique",
        "resume", "costume", "fortune",
        "ature", "nature", "future", "mature", "posture",
        "measure", "treasure", "pleasure",
        "russia", "russian", "siberia",
        "toronto", "ohio", "waikiki", "oahu",
        "sudden", "happen", "kitten", "mitten", "bitten", "rotten", "gotten",
        "women", "woman",
        "minute", "ribute", "absolute",
        "were", "here", "mere", "there", "where",
        "undue", "undo", "unto",
        "semi", "anti",
        "originate", "dominate", "nominate", "terminate", "estimate",
        "situation", "reputation", "population", "operation", "generation",
        "sensation", "combination", "imagination", "destination",
        "possession", "opposition", "composition", "proposition",
        "refugee", "guarantee",
        "wanton", "pardon",
        "taboo", "bamboo", "shampoo", "tattoo",
        "zero", "hero", "nero",
        "yankee",
        "yoke", "woke", "joke", "poke", "smoke", "broke", "spoke", "choke",
        "shake", "shaken",
        "shore", "share",
        "since", "once", "hence", "fence", "prince",
        "bone", "stone", "phone", "throne", "ozone",
        "remain", "obtain", "contain", "maintain", "sustain", "retain",
        "pain", "rain", "gain", "main", "vain", "brain", "train", "grain", "drain",
        "ruin",
        "basin",
        "again", "arose", "arrange", "ashore", "aside", "attitude", "aurora",
        "automaton", "awaken",
        "beau", "been", "began", "begin", "begun", "beside", "bizarre",
        "bohemian", "bonanza",
        "chain", "change", "cherokee", "china", "chinese", "chosen",
        "dante", "date", "debutante", "desire", "disease", "doggone", "don", "dozen",
        "eaten", "ego", "emma", "emotion", "endure", "engage",
        "eurasian", "europe", "eye",
        "gaze", "geese", "goose",
        "harrison", "hate", "hawaii", "hawaiian", "hope", "house", "human",
        "idea", "indian", "insinuate", "intention", "into", "iota", "irate", "iron", "irritation",
        "japanese", "jeanne", "jesse", "joan", "joe", "jose", "joshua", "junta",
        "made", "magazine", "massage", "mate", "maui", "mean", "men", "mention",
        "mirage", "moon", "moore", "moose",
        "nope", "onto",
        "patino", "pierre",
        "rancho", "rate", "refuge", "repose",
        "seen", "soon", "suppose",
        "tirade",
        "wise", "yea", "yukon",
        "oona", "ooze", "wada", "weren", "unwin",
        "naomi", "niihau", "dennin", "doane", "hanrahan", "howison", "nakata",
        "ee", "san"
    ]

    private static func normalizeRomaji(_ word: String) -> String {
        var w = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let macronMap = ["ā": "a", "ī": "i", "ū": "u", "ē": "e", "ō": "o"]
        for (k, v) in macronMap {
            w = w.replacingOccurrences(of: k, with: v)
        }
        w = w.folding(options: .diacriticInsensitive, locale: nil)
        return w
    }

    private static func simplifySokuon(_ word: String) -> (String, [Int: Character]) {
        let chars = Array(word)
        var result: [Character] = []
        var sokuonBefore: [Int: Character] = [:]
        var i = 0
        while i < chars.count {
            if i < chars.count - 1 && chars[i] == chars[i+1] && !"aeiou".contains(chars[i]) {
                sokuonBefore[result.count] = chars[i]
                result.append(chars[i])
                i += 2
            } else {
                result.append(chars[i])
                i += 1
            }
        }
        return (String(result), sokuonBefore)
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
        if word.count < 2 { return false }

        let normalized = normalizeRomaji(word)

        if englishBlacklist.contains(normalized) { return false }

        for ch in normalized {
            if "lqvx".contains(ch) { return false }
        }

        let range = NSRange(location: 0, length: normalized.utf16.count)
        if PreprocessorRegex.asciiLettersOnly.firstMatch(in: normalized, options: [], range: range) == nil {
            return false
        }

        let (simplified, _) = simplifySokuon(normalized)
        guard let syllables = greedySegment(simplified) else { return false }

        return syllables.count >= 2
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

        var merged: [String] = []
        i = 0
        while i < viSyllables.count {
            if viSyllables[i] == "n" && i > 0 && !merged.isEmpty {
                merged[merged.count - 1] = merged[merged.count - 1] + "n"
                i += 1
            } else {
                merged.append(viSyllables[i])
                i += 1
            }
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
                        let mergedIdx = findMergedIndex(syllables: syllables, mergedCount: merged.count, sylIndex: si)
                        if mergedIdx > 0 && mergedIdx < merged.count {
                            let sokuVi = sokuonCoda(sokuChar)
                            merged[mergedIdx - 1] = merged[mergedIdx - 1] + sokuVi
                        }
                        break
                    }
                }
            }
        }

        return merged.joined(separator: "-")
    }

    private static func findMergedIndex(syllables: [String], mergedCount: Int, sylIndex: Int) -> Int {
        var mi = 0
        for si in 0..<syllables.count {
            if si == sylIndex {
                return mi
            }
            if syllables[si] != "n" || si == 0 {
                mi += 1
            }
        }
        return mi
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
