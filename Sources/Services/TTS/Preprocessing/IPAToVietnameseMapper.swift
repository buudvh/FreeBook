import Foundation

/// Chuyển chuỗi **IPA** thành âm tiết tiếng Việt đọc được.
///
/// Vì sao cần nó: bộ luật cũ (`EnglishTransliterator`) đoán phát âm từ **chính tả** tiếng Anh, việc
/// bất khả về nguyên tắc ("one", "though", "colonel" không có luật nào đúng). espeak-ng đã nằm trong
/// app kèm `en_dict`, nên hỏi nó lấy IPA thật rồi map **âm vị → âm tiết Việt** là bài toán đóng: ~50
/// dòng bảng kiểm được từng dòng, thay cho ~200 regex chính tả không kiểm được.
///
/// Bất biến quan trọng: đầu ra phải là **âm tiết tiếng Việt hợp lệ**, vì nó lại được espeak (giọng
/// `vi`) phiên âm tiếp cho Piper. Chuỗi không hợp lệ (`ơng`, `âyp`, coda `s`, cụm `str`, hay âm tiết
/// đóng bằng phụ âm tắc mà **không dấu**) làm espeak-vi đọc sai hoặc bỏ qua. Năm luật ép hợp lệ nằm ở
/// `legalOnset`, `legalCoda`, `diphthongs` (nguyên âm đôi không nhận phụ âm cuối), `acute` (dấu sắc bắt
/// buộc cho coda tắc) và `normalize`.
enum IPAToVietnameseMapper {

    /// Nguyên âm đơn và đôi. Nguyên âm đôi phải đứng **trước** trong thứ tự dò vì khớp dài nhất.
    private static let vowels: [(ipa: String, vi: String)] = [
        ("eɪ", "ây"), ("aɪ", "ai"), ("ɔɪ", "oi"), ("aʊ", "ao"), ("oʊ", "ô"), ("əʊ", "ô"),
        ("ɪə", "ia"), ("eə", "e"), ("ʊə", "ua"), ("juː", "iu"), ("ju", "iu"),
        ("iː", "i"), ("uː", "u"), ("ɑː", "a"), ("ɔː", "o"), ("ɜː", "ơ"), ("ɪ", "i"),
        // `ʌ` → `â`, **không** phải `ơ`: tiếng Việt không có rime `ơng`, nên "young" từng ra `dơng` —
        // một chuỗi không tồn tại. Với `â` thì `âng âp ât âc âm ân` đều hợp lệ ("young" → "dâng").
        ("ʊ", "u"), ("æ", "a"), ("ɑ", "a"), ("ɒ", "o"), ("ɔ", "o"), ("ʌ", "â"),
        ("ə", "ơ"), ("ɛ", "e"), ("e", "ê"), ("i", "i"), ("u", "u"), ("o", "ô"), ("a", "a"),
        // Ký hiệu riêng của espeak-ng cho en-us. Không khai thì `tokenize` bỏ qua âm đó và cả từ mất
        // tiếng, nên phải phủ hết những cái hay gặp.
        ("ɐ", "a"), ("ᵻ", "i"), ("ɚ", "ơ"), ("ɵ", "ơ"), ("ɨ", "i")
    ]

    /// Phụ âm ở **đầu** âm tiết.
    private static let onsets: [(ipa: String, vi: String)] = [
        ("tʃ", "ch"), ("dʒ", "gi"), ("ʃ", "s"), ("ʒ", "gi"), ("θ", "th"), ("ð", "đ"),
        // `j` ở đầu âm tiết → `d` (không phải `i`): viết `i` thì espeak-vi đọc `ia`/`iơ` thành nguyên
        // âm đôi nên "yes" ra hai âm tiết. Cùng lựa chọn với `ya/yu/yo` của `JapaneseTransliterator`.
        // Hàng `j` trong bảng `codas` **vẫn là `i`** — ở đó nó là bán nguyên âm cuối của `ai`, `ây`.
        ("ŋ", "ng"), ("ɡ", "g"), ("g", "g"), ("ɹ", "r"), ("r", "r"), ("j", "d"),
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

    /// Nguyên âm đôi. Trong tiếng Việt chúng **không nhận phụ âm cuối** — `âyp`, `aip`, `aok` không
    /// tồn tại — nên `split` phải đẩy toàn bộ phụ âm giữa hai nguyên âm sang âm tiết sau, và `assemble`
    /// bỏ coda khi đã hết âm tiết để đẩy. Đây là chỗ "april" từng ra `âyp-rơn`, một chuỗi người Việt
    /// không đọc được.
    private static let diphthongs: Set<String> = ["ây", "ai", "oi", "ao", "ia", "ua", "iu"]

    /// Phụ âm cuối tắc. Tiếng Việt **không có** âm tiết nào vừa đóng bằng nhóm này vừa không dấu, nên
    /// mọi âm tiết như vậy bắt buộc mang dấu sắc (`trit` → `trít`, `tat` → `tát`).
    private static let stopCodas: Set<String> = ["p", "t", "c", "ch"]

    /// Dấu sắc. Chỉ cần bảng **một ký tự**: nhờ luật `diphthongs`, mọi âm tiết cần đánh dấu ở đây đều
    /// có nucleus là một nguyên âm đơn.
    private static let acuteVowels: [Character: Character] = [
        "a": "á", "ă": "ắ", "â": "ấ", "e": "é", "ê": "ế", "i": "í",
        "o": "ó", "ô": "ố", "ơ": "ớ", "u": "ú", "ư": "ứ", "y": "ý"
    ]

    /// Rime cố định của âm tiết giảm nhẹ `/əl/` và `/ən/`, mang **dấu huyền** — đúng cách người Việt
    /// đọc "google" → "gu-gồ", "colonel" → "cơ-nồ", "station" → "…-sình". Khoá là **ký hiệu IPA** chứ
    /// không phải coda đã map, vì `l`, `ɫ` và `n` đều cho coda `"n"` nên sau khi map thì không còn phân
    /// biệt được `/əl/` với `/ən/`.
    private static let reducedRimes: [String: String] = ["l": "ồ", "ɫ": "ồ", "n": "ình"]

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
    /// cùng của chuỗi phụ âm giữa hai nguyên âm, đúng quy tắc maximal onset — **trừ** khi âm tiết đang
    /// dựng có nucleus là nguyên âm đôi: khi đó nó không nhận được phụ âm cuối nào, nên **toàn bộ** cụm
    /// phụ âm phải sang âm tiết sau ("april" ⇒ `ây` + `pɹəl`, không phải `âyp` + `ɹəl`).
    private static func split(units: [String]) -> [[String]] {
        var syllables: [[String]] = []
        var current: [String] = []
        var seenVowel = false

        for unit in units {
            if isVowel(unit) {
                if seenVowel {
                    let carryAll = endsWithDiphthong(current)
                    var carried: [String] = []
                    while let last = current.last, !isVowel(last), carryAll || carried.count < 1 {
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

    /// Nucleus của âm tiết đang dựng có phải nguyên âm đôi — tức không nhận được phụ âm cuối.
    private static func endsWithDiphthong(_ units: [String]) -> Bool {
        guard let vowelUnit = units.last(where: { isVowel($0) }),
              let vi = vowels.first(where: { $0.ipa == vowelUnit })?.vi else { return false }
        return diphthongs.contains(vi)
    }

    /// Dựng **các** âm tiết Việt hợp lệ cho một âm tiết IPA.
    ///
    /// Trả về mảng chứ không phải một chuỗi vì tiếng Việt không có cụm phụ âm đầu: cụm đó phải **tách
    /// thành âm tiết đệm** (`+ "ơ"`) chứ không được bỏ ("street" → `xơ` + `trít`).
    ///
    /// Phần **thừa ở cuối** thì ngược lại: bị **bỏ**. Bản 1.3.291 đọc nó thành một âm tiết đệm nữa
    /// ("task" → `tat-cơ`, "text" → `tếc-xơ`); đó là đảo lại theo yêu cầu người dùng — âm gió cuối của
    /// tiếng Anh không có chỗ trong âm tiết tiếng Việt, thà mất nó còn hơn thêm một tiếng lạ.
    private static func assemble(_ units: [String]) -> [String] {
        guard let vowelIndex = units.firstIndex(where: { isVowel($0) }) else {
            // Âm tiết không có nguyên âm: đọc từng phụ âm thành một âm tiết đệm, không bỏ chữ nào.
            return units.compactMap { unit in
                onsets.first(where: { $0.ipa == unit })?.vi
            }.map { normalize(onset: $0, nucleus: "ơ", coda: "") }
        }

        let vowelUnit = units[vowelIndex]
        let onsetUnits = Array(units[units.startIndex..<vowelIndex])
        let codaUnits = Array(units[(vowelIndex + 1)...])
        guard let nucleus = vowels.first(where: { $0.ipa == vowelUnit })?.vi else { return [] }

        let onset = legalOnset(onsetUnits)
        var result = onset.leading.map { normalize(onset: $0, nucleus: "ơ", coda: "") }

        // `/əl/` và `/ən/` là rime cố định mang dấu huyền, không đi qua bảng coda.
        if vowelUnit == "ə", let reduced = reducedRime(codaUnits) {
            result.append(normalize(onset: onset.head, nucleus: reduced, coda: ""))
            return result
        }

        // Nguyên âm đôi không nhận phụ âm cuối. `split` đã đẩy cụm sang âm tiết sau khi còn âm tiết để
        // đẩy; tới đây là cuối từ nên bỏ coda.
        let coda = diphthongs.contains(nucleus) ? "" : legalCoda(codaUnits)
        result.append(normalize(onset: onset.head, nucleus: nucleus, coda: coda))
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

    /// Phụ âm cuối **đầu tiên** hợp lệ. Phần còn lại bị bỏ (xem `assemble`).
    private static func legalCoda(_ units: [String]) -> String {
        for unit in units {
            if let coda = codas[unit], !coda.isEmpty { return coda }
        }
        return ""
    }

    /// Rime cố định khi phụ âm cuối **đầu tiên** là `l`/`ɫ`/`n` — chỉ dùng cho nucleus `ə`.
    private static func reducedRime(_ units: [String]) -> String? {
        for unit in units {
            if let reduced = reducedRimes[unit] { return reduced }
            if let coda = codas[unit], !coda.isEmpty { return nil }
        }
        return nil
    }

    /// Ba chỗ chính tả tiếng Việt bắt buộc: dấu sắc cho coda tắc, `c/k/g/gh/ng/ngh` theo nguyên âm sau,
    /// và nguyên âm ngắn `ă/â` không đứng một mình.
    private static func normalize(onset: String, nucleus: String, coda: String) -> String {
        var body = nucleus
        // Sống lại từ 1.3.305: trước khi có `ʌ → â` thì bảng nguyên âm không sinh ra `â` nào nên nhánh
        // này là code chết. Nay `/ʌ/` ở âm tiết mở phải về `ơ` vì `â` đứng một mình không phải âm tiết.
        if coda.isEmpty, body == "ă" || body == "â" {
            body = "ơ"
        }
        if stopCodas.contains(coda) {
            body = acute(body)
        }

        // Xét trên **chữ đã bỏ dấu thanh**: `ế`, `í` vẫn là nguyên âm trước, nên `k`/`gh`/`ngh` vẫn phải
        // áp. So sánh trực tiếp với "iêe" như bản cũ thì mọi âm tiết có dấu đều trượt luật này.
        let frontVowel = body.first
            .map { String($0).folding(options: .diacriticInsensitive, locale: nil).lowercased() }
            .map { "ie".contains($0) } ?? false

        var head = onset
        if head == "c" && frontVowel { head = "k" }
        if head == "k" && !frontVowel { head = "c" }
        if head == "g" && frontVowel { head = "gh" }
        if head == "gh" && !frontVowel { head = "g" }
        if head == "ng" && frontVowel { head = "ngh" }

        return head + body + coda
    }

    private static func acute(_ nucleus: String) -> String {
        guard nucleus.count == 1, let first = nucleus.first, let marked = acuteVowels[first] else {
            return nucleus
        }
        return String(marked)
    }
}
