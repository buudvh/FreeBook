import Foundation

/// Chuyển chuỗi **IPA** thành âm tiết tiếng Việt đọc được.
///
/// Vì sao cần nó: bộ luật cũ (`EnglishTransliterator`) đoán phát âm từ **chính tả** tiếng Anh, việc
/// bất khả về nguyên tắc ("one", "though", "colonel" không có luật nào đúng). espeak-ng đã nằm trong
/// app kèm `en_dict`, nên hỏi nó lấy IPA thật rồi map **âm vị → âm tiết Việt** là bài toán đóng: ~50
/// dòng bảng kiểm được từng dòng, thay cho ~200 regex chính tả không kiểm được.
///
/// Bất biến quan trọng: đầu ra phải là **âm tiết tiếng Việt hợp lệ**, vì nó lại được espeak (giọng
/// `vi`) phiên âm tiếp cho Piper. Chuỗi không hợp lệ (`ă` đứng một mình, coda `s`, cụm `str`) làm
/// espeak-vi đọc sai hoặc bỏ qua. Ba luật ép hợp lệ nằm ở `legalOnset`, `legalCoda` và `assemble`.
enum IPAToVietnameseMapper {

    /// Nguyên âm đơn và đôi. Nguyên âm đôi phải đứng **trước** trong thứ tự dò vì khớp dài nhất.
    private static let vowels: [(ipa: String, vi: String)] = [
        ("eɪ", "ây"), ("aɪ", "ai"), ("ɔɪ", "oi"), ("aʊ", "ao"), ("oʊ", "ô"), ("əʊ", "ô"),
        ("ɪə", "ia"), ("eə", "e"), ("ʊə", "ua"), ("juː", "iu"), ("ju", "iu"),
        ("iː", "i"), ("uː", "u"), ("ɑː", "a"), ("ɔː", "o"), ("ɜː", "ơ"), ("ɪ", "i"),
        ("ʊ", "u"), ("æ", "a"), ("ɑ", "a"), ("ɒ", "o"), ("ɔ", "o"), ("ʌ", "ơ"),
        ("ə", "ơ"), ("ɛ", "e"), ("e", "ê"), ("i", "i"), ("u", "u"), ("o", "ô"), ("a", "a"),
        // Ký hiệu riêng của espeak-ng cho en-us. Không khai thì `tokenize` bỏ qua âm đó và cả từ mất
        // tiếng, nên phải phủ hết những cái hay gặp.
        ("ɐ", "a"), ("ᵻ", "i"), ("ɚ", "ơ"), ("ɵ", "ơ"), ("ɨ", "i")
    ]

    /// Phụ âm ở **đầu** âm tiết.
    private static let onsets: [(ipa: String, vi: String)] = [
        ("tʃ", "ch"), ("dʒ", "gi"), ("ʃ", "s"), ("ʒ", "gi"), ("θ", "th"), ("ð", "đ"),
        ("ŋ", "ng"), ("ɡ", "g"), ("g", "g"), ("ɹ", "r"), ("r", "r"), ("j", "i"),
        ("w", "o"), ("h", "h"), ("p", "p"), ("b", "b"), ("t", "t"), ("d", "đ"),
        ("k", "c"), ("f", "ph"), ("v", "v"), ("s", "x"), ("z", "d"), ("m", "m"),
        ("n", "n"), ("l", "l"), ("ɫ", "l"), ("ɾ", "r"), ("ʁ", "r")
    ]

    /// Phụ âm ở **cuối** âm tiết. Tiếng Việt chỉ cho `p t c ch m n ng nh` + bán nguyên âm, nên mọi
    /// coda khác phải quy về nhóm đó chứ không được giữ nguyên.
    private static let codas: [String: String] = [
        "p": "p", "b": "p", "f": "p", "v": "p",
        "t": "t", "d": "t", "θ": "t", "ð": "t", "s": "t", "z": "t",
        "k": "c", "ɡ": "c", "g": "c",
        "tʃ": "ch", "dʒ": "ch", "ʃ": "ch", "ʒ": "ch",
        "m": "m", "n": "n", "ŋ": "ng", "l": "n", "ɫ": "n",
        "ɹ": "", "r": "", "ɾ": "", "h": "", "j": "i", "w": "o", "ʔ": ""
    ]

    /// Onset hai chữ hợp lệ của tiếng Việt. Cụm không có trong đây bị rút về **phụ âm cuối** của cụm
    /// (đúng cách bộ luật cũ làm: `str` → `tr`, `bl` → `l`, `sp` → `p`).
    private static let legalDoubleOnsets: Set<String> = ["ch", "gh", "gi", "kh", "ng", "nh", "ph", "qu", "th", "tr"]

    private static let stressMarks: Set<Character> = ["ˈ", "ˌ", "ː", "‿", "|", "‖", "ʰ", "̩", "̯", "ˑ", "˞", "ʲ", "ˠ", "̃"]

    // MARK: - Vào / ra

    /// `ipa` là chuỗi âm vị của **một** từ. Trả về các âm tiết Việt nối bằng `-`, hoặc rỗng khi không
    /// đọc được gì (caller sẽ rơi về bộ luật cũ).
    static func transliterate(ipa: String) -> String {
        let cleaned = String(ipa.filter { !stressMarks.contains($0) && !$0.isWhitespace })
        guard !cleaned.isEmpty else { return "" }

        let units = tokenize(cleaned)
        guard !units.isEmpty else { return "" }

        let syllables = split(units: units)
        let rendered = syllables.compactMap { assemble($0) }.filter { !$0.isEmpty }
        return rendered.joined(separator: "-")
    }

    /// Cắt IPA thành đơn vị âm vị, ưu tiên khớp **dài nhất** (hai ký tự trước một ký tự) để `tʃ`,
    /// `eɪ`, `iː` không bị xé thành hai.
    private static func tokenize(_ ipa: String) -> [String] {
        let chars = Array(ipa)
        var result: [String] = []
        var cursor = 0

        while cursor < chars.count {
            var matched = false
            for length in [3, 2, 1] where cursor + length <= chars.count {
                let candidate = String(chars[cursor..<(cursor + length)])
                if vowels.contains(where: { $0.ipa == candidate }) || onsets.contains(where: { $0.ipa == candidate }) {
                    result.append(candidate)
                    cursor += length
                    matched = true
                    break
                }
            }
            if !matched {
                cursor += 1
            }
        }
        return result
    }

    private static func isVowel(_ unit: String) -> Bool {
        vowels.contains { $0.ipa == unit }
    }

    /// Một âm tiết = (phụ âm đầu…) + nguyên âm + (phụ âm cuối…). Ranh giới đặt **trước** phụ âm cuối
    /// cùng của chuỗi phụ âm giữa hai nguyên âm, đúng quy tắc maximal onset.
    private static func split(units: [String]) -> [[String]] {
        var syllables: [[String]] = []
        var current: [String] = []
        var seenVowel = false

        for unit in units {
            if isVowel(unit) {
                if seenVowel {
                    // Nguyên âm thứ hai: nhả phụ âm cuối cùng sang âm tiết mới làm onset.
                    var carried: [String] = []
                    while let last = current.last, !isVowel(last), carried.count < 1 {
                        carried.insert(last, at: 0)
                        current.removeLast()
                    }
                    syllables.append(current)
                    current = carried
                }
                current.append(unit)
                seenVowel = true
            } else {
                current.append(unit)
            }
        }

        if !current.isEmpty { syllables.append(current) }
        return syllables
    }

    /// Dựng một âm tiết Việt hợp lệ từ các đơn vị IPA của nó.
    private static func assemble(_ units: [String]) -> String? {
        guard let vowelIndex = units.firstIndex(where: { isVowel($0) }) else {
            // Âm tiết không có nguyên âm (cụm phụ âm lạc) — đọc thành phụ âm + "ơ" để không mất chữ.
            guard let first = units.first, let onset = onsets.first(where: { $0.ipa == first })?.vi else { return nil }
            return onset + "ơ"
        }

        let onset = legalOnset(Array(units[units.startIndex..<vowelIndex]))
        guard let nucleus = vowels.first(where: { $0.ipa == units[vowelIndex] })?.vi else { return nil }
        let coda = legalCoda(Array(units[(vowelIndex + 1)...]))

        return normalize(onset: onset, nucleus: nucleus, coda: coda)
    }

    private static func legalOnset(_ units: [String]) -> String {
        let mapped = units.compactMap { unit in onsets.first(where: { $0.ipa == unit })?.vi }
        guard !mapped.isEmpty else { return "" }
        if mapped.count == 1 { return mapped[0] }

        // Thử ghép hai phụ âm cuối thành onset đôi hợp lệ; không được thì lấy phụ âm cuối.
        let tail = mapped.suffix(2).joined()
        if legalDoubleOnsets.contains(tail) { return tail }
        return mapped[mapped.count - 1]
    }

    private static func legalCoda(_ units: [String]) -> String {
        for unit in units {
            if let coda = codas[unit], !coda.isEmpty { return coda }
        }
        return ""
    }

    /// Ba chỗ chính tả tiếng Việt bắt buộc: `c/k/q` theo nguyên âm sau, `g/gh`, và nguyên âm ngắn
    /// `ă/â` không đứng một mình.
    private static func normalize(onset: String, nucleus: String, coda: String) -> String {
        var head = onset
        let frontVowel = nucleus.first.map { "iêe".contains($0) } ?? false

        if head == "c" && frontVowel { head = "k" }
        if head == "k" && !frontVowel { head = "c" }
        if head == "g" && frontVowel { head = "gh" }
        if head == "gh" && !frontVowel { head = "g" }
        if head == "ng" && frontVowel { head = "ngh" }

        var body = nucleus
        if coda.isEmpty, body == "ă" || body == "â" {
            body = "ơ"
        }
        return head + body + coda
    }
}
