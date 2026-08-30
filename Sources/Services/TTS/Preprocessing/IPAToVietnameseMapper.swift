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
        let rendered = syllables.flatMap { assemble($0) }.filter { !$0.isEmpty }
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

    /// Dựng **các** âm tiết Việt hợp lệ cho một âm tiết IPA.
    ///
    /// Trả về mảng chứ không phải một chuỗi vì tiếng Việt không có cụm phụ âm: cụm đầu và phần thừa ở
    /// cuối phải **tách thành âm tiết đệm** (`+ "ơ"`) chứ không được bỏ. Bản 1.3.290 giữ đúng một phụ âm
    /// mỗi đầu và bỏ phần còn lại — đó chính là chỗ "street" mất /s/ và "text" mất đuôi.
    private static func assemble(_ units: [String]) -> [String] {
        guard let vowelIndex = units.firstIndex(where: { isVowel($0) }) else {
            // Âm tiết không có nguyên âm: đọc từng phụ âm thành một âm tiết đệm, không bỏ chữ nào.
            return units.compactMap { unit in
                onsets.first(where: { $0.ipa == unit })?.vi
            }.map { normalize(onset: $0, nucleus: "ơ", coda: "") }
        }

        let onsetUnits = Array(units[units.startIndex..<vowelIndex])
        let codaUnits = Array(units[(vowelIndex + 1)...])
        guard let nucleus = vowels.first(where: { $0.ipa == units[vowelIndex] })?.vi else { return [] }

        let onset = legalOnset(onsetUnits)
        var result = onset.leading.map { normalize(onset: $0, nucleus: "ơ", coda: "") }
        result.append(normalize(onset: onset.head, nucleus: nucleus, coda: legalCoda(codaUnits)))
        if let trailing = trailingFiller(codaUnits) {
            result.append(normalize(onset: trailing, nucleus: "ơ", coda: ""))
        }
        return result
    }

    /// `head` là phụ âm đầu thật; `leading` là các phụ âm đứng trước nó, mỗi cái thành một âm tiết đệm
    /// ("street" → leading `["x", "t"]`, head `"r"` ⇒ "xơ-tơ-rít").
    private static func legalOnset(_ units: [String]) -> (leading: [String], head: String) {
        let mapped = units.compactMap { unit in onsets.first(where: { $0.ipa == unit })?.vi }
        guard !mapped.isEmpty else { return ([], "") }
        if mapped.count == 1 { return ([], mapped[0]) }

        // Hai phụ âm cuối ghép được thành onset đôi hợp lệ thì giữ nguyên cả cặp.
        let tail = mapped.suffix(2).joined()
        if legalDoubleOnsets.contains(tail) {
            return (Array(mapped.dropLast(2)), tail)
        }
        return (Array(mapped.dropLast()), mapped[mapped.count - 1])
    }

    /// Phụ âm cuối **đầu tiên** hợp lệ. Phần còn lại do `trailingFiller` lo, không bị bỏ.
    private static func legalCoda(_ units: [String]) -> String {
        for unit in units {
            if let coda = codas[unit], !coda.isEmpty { return coda }
        }
        return ""
    }

    /// Phụ âm còn lại sau coda, đọc thành **một** âm tiết đệm ("text" → "tếc-xơ"). Cố ý chỉ lấy một:
    /// đọc hết mọi phụ âm thừa làm câu dài và lạ hơn là mất một âm.
    private static func trailingFiller(_ units: [String]) -> String? {
        var seenCoda = false
        for unit in units {
            guard let coda = codas[unit], !coda.isEmpty else { continue }
            if !seenCoda {
                seenCoda = true
                continue
            }
            return onsets.first(where: { $0.ipa == unit })?.vi
        }
        return nil
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
