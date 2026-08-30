import Foundation

/// Quyết định một từ Latin là **romaji tiếng Nhật** hay **tiếng Anh**, bằng điểm dấu hiệu thay cho
/// blacklist tay.
///
/// Vì sao phải đổi: bản cũ coi *mọi* từ cắt được thành âm romaji là tiếng Nhật, rồi chống đỡ bằng một
/// `englishBlacklist` ~420 từ vá theo từng ca báo lỗi. Nhưng "tomato", "potato", "sonata", "sedan"…
/// đều là chuỗi romaji hợp lệ — tập từ tiếng Anh cần loại trừ là **vô hạn**, nên cách đó không bao giờ
/// đúng được. Ở đây romaji hợp lệ chỉ còn là *điều kiện cần*; điểm mới quyết định.
///
/// Nguyên tắc chấm: dấu hiệu **chỉ có** ở romaji (`tsu`, `ryu`, `kyo`, sokuon, `n` trước phụ âm, đuôi
/// nguyên âm mở) cộng điểm; dấu hiệu **không thể** có trong romaji Hepburn (chữ `l/q/v/x/f` ngoài `fu`,
/// cụm phụ âm, đuôi `-ing/-ed/-tion/-ly/-er`, nguyên âm đôi kiểu Anh) trừ điểm rất nặng.
enum ForeignScriptClassifier {

    /// Âm tiết romaji Hepburn hợp lệ. Cố ý **không** dùng bảng map của `JapaneseTransliterator`: bảng
    /// đó là bảng *đọc*, còn đây là bảng *nhận dạng*, hai việc khác nhau và đổi độc lập.
    private static let syllables: Set<String> = {
        var result: Set<String> = ["n"]
        let onsets = ["", "k", "s", "t", "n", "h", "m", "y", "r", "w", "g", "z", "d", "b", "p"]
        let vowels = ["a", "i", "u", "e", "o"]
        for onset in onsets {
            for vowel in vowels {
                result.insert(onset + vowel)
            }
        }
        for palatal in ["ky", "sh", "ch", "ny", "hy", "my", "ry", "gy", "j", "by", "py"] {
            for vowel in ["a", "u", "o"] {
                result.insert(palatal + vowel)
            }
        }
        for extra in ["shi", "chi", "tsu", "fu", "ji", "she", "che", "je", "ti", "di", "tu", "du",
                      "aa", "ii", "uu", "ee", "oo"] {
            result.insert(extra)
        }
        return result
    }()

    /// Đuôi hình thái tiếng Anh: có một cái là gần như chắc chắn không phải romaji.
    private static let englishSuffixes = ["ing", "ed", "tion", "sion", "ly", "ness", "ment", "able",
                                          "ible", "ful", "less", "est", "ism", "ist", "ous", "ive"]

    /// Cụm chữ không tồn tại trong romaji Hepburn.
    private static let englishClusters = ["th", "ph", "wh", "ck", "gh", "sc", "sp", "st", "sk", "sl",
                                          "sm", "sn", "sw", "tr", "dr", "pr", "br", "cr", "gr", "fr",
                                          "bl", "cl", "fl", "gl", "pl", "nt", "nd", "mp", "ng", "rt",
                                          "rd", "rn", "rm", "rl", "lt", "ld", "lm", "lf", "ct", "pt",
                                          "xt", "ea", "ou", "ai", "oa", "ie", "ei", "au", "aw", "ow",
                                          "oi", "oy", "ay", "ey"]

    /// Điểm tối thiểu để coi là tiếng Nhật. Ngưỡng đo bằng `TransliterationGoldenSet` — đổi số này thì
    /// phải chạy lại bộ ca kiểm ở màn Thử phiên âm.
    static let japaneseThreshold = 2

    struct Verdict {
        let isJapanese: Bool
        let score: Int
        let reasons: [String]
    }

    static func isJapaneseRomaji(_ word: String) -> Bool {
        classify(word).isJapanese
    }

    static func classify(_ word: String) -> Verdict {
        var reasons: [String] = []
        let normalized = normalize(word)

        guard normalized.count >= 2 else {
            return Verdict(isJapanese: false, score: -99, reasons: ["quá ngắn"])
        }
        guard normalized.allSatisfy({ $0.isLetter && $0.isASCII }) else {
            return Verdict(isJapanese: false, score: -99, reasons: ["có ký tự không phải chữ ASCII"])
        }

        // Chữ không tồn tại trong Hepburn ⇒ loại thẳng, không cần chấm điểm.
        for character in normalized where "lqvx".contains(character) {
            return Verdict(isJapanese: false, score: -99, reasons: ["có chữ '\(character)' không có trong romaji"])
        }

        let (simplified, sokuonCount) = simplifySokuon(normalized)
        guard let parts = segment(simplified) else {
            return Verdict(isJapanese: false, score: -99, reasons: ["không cắt được thành âm romaji"])
        }
        guard parts.count >= 2 else {
            return Verdict(isJapanese: false, score: -99, reasons: ["chỉ có một âm tiết"])
        }

        var score = 0

        for suffix in englishSuffixes where normalized.hasSuffix(suffix) {
            score -= 3
            reasons.append("đuôi tiếng Anh '-\(suffix)' (-3)")
            break
        }

        var clusterHits = 0
        for cluster in englishClusters where normalized.contains(cluster) {
            clusterHits += 1
        }
        if clusterHits > 0 {
            score -= 2 * clusterHits
            reasons.append("\(clusterHits) cụm chữ kiểu Anh (-\(2 * clusterHits))")
        }

        for marker in ["tsu", "ryu", "ryo", "kyo", "kyu", "shu", "sho", "cha", "chu", "cho", "gyo"] {
            guard simplified.contains(marker) else { continue }
            score += 2
            reasons.append("âm đặc trưng '\(marker)' (+2)")
        }

        if sokuonCount > 0 {
            score += 2
            reasons.append("phụ âm đôi kiểu sokuon (+2)")
        }

        if let last = simplified.last, "aiueo".contains(last) {
            score += 1
            reasons.append("kết thúc bằng nguyên âm (+1)")
        }

        if parts.contains("n"), parts.count >= 3 {
            score += 1
            reasons.append("có 'n' làm âm tiết riêng (+1)")
        }

        if normalized.count >= 6, clusterHits == 0 {
            score += 1
            reasons.append("từ dài mà không có cụm phụ âm Anh (+1)")
        }

        let isJapanese = score >= japaneseThreshold
        reasons.append("tổng \(score) so với ngưỡng \(japaneseThreshold)")
        return Verdict(isJapanese: isJapanese, score: score, reasons: reasons)
    }

    // MARK: - Phụ trợ

    private static func normalize(_ word: String) -> String {
        var value = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for (macron, plain) in [("ā", "a"), ("ī", "i"), ("ū", "u"), ("ē", "e"), ("ō", "o")] {
            value = value.replacingOccurrences(of: macron, with: plain)
        }
        return value.folding(options: .diacriticInsensitive, locale: nil)
    }

    private static func simplifySokuon(_ word: String) -> (String, Int) {
        let chars = Array(word)
        var result: [Character] = []
        var count = 0
        var index = 0
        while index < chars.count {
            if index < chars.count - 1, chars[index] == chars[index + 1], !"aiueo".contains(chars[index]) {
                count += 1
                result.append(chars[index])
                index += 2
            } else {
                result.append(chars[index])
                index += 1
            }
        }
        return (String(result), count)
    }

    /// Cắt greedy dài → ngắn. `n` đơn chỉ được nhận khi **không** đứng trước nguyên âm hay `y`, vì khi
    /// đó nó thuộc âm tiết sau (`na`, `nya`).
    private static func segment(_ word: String) -> [String]? {
        var parts: [String] = []
        let chars = Array(word)
        var index = 0

        while index < chars.count {
            var matched = false
            for length in [3, 2, 1] where index + length <= chars.count {
                let candidate = String(chars[index..<(index + length)])
                guard syllables.contains(candidate) else { continue }
                if candidate == "n", length == 1, index + 1 < chars.count, "aiueoy".contains(chars[index + 1]) {
                    continue
                }
                parts.append(candidate)
                index += length
                matched = true
                break
            }
            if !matched { return nil }
        }
        return parts
    }
}
