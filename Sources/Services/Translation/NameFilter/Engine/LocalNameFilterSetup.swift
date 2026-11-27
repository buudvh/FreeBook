import Foundation

/// Bảng tra dựng **một** lần mỗi lượt lọc từ `LocalNameFilter.Configuration` + bản chụp từ điển — phần `Config` của bản
/// thử Python (`local_name_filter2.py` + `lacpipe.py`). Bất biến sau khi dựng.
///
/// Đuôi (cách A, 2026-11-27, anh Bửu): **dò** dùng bộ cố định `detectionSuffixes` = file gốc `NameFilterSuffixes.txt` trừ
/// dòng `|off` (`LocalNameFilterSuffixStore.detectionSuffixes`), **không** theo danh sách người dùng — cấu hình mặc định
/// cho đúng số liệu như trước. Bộ dò chia hai đường như Python:
/// - **bộ luật** chỉ thấy đuôi `place` / `sect` (sinh ứng viên, `suffix_chars`, lọc danh xưng) — đuôi `term` không bao
///   giờ sinh ứng viên;
/// - **phía LAC** thấy mọi đuôi dò (`SUFFIXES` của `lacpipe.py`): phân loại thực thể, luật "tên + 1 chữ". Từ plan
///   2026-11-27-phan-loai-name (L11) bộ dò phía LAC có thêm hậu tố **Nhân danh** 2–6 chữ của bản gốc (name có hậu tố đó
///   ⇒ Nhân danh: 天元圣女); luật (e) và bộ luật không dùng chúng.
/// Danh sách người dùng (`Configuration.suffixes`) **chỉ** để ghép nghĩa, chia theo loại: đuôi địa danh / tổ chức / thuật
/// ngữ ghép nghĩa name không phải người (`meaningSuffix`); đuôi Nhân danh là danh xưng — `pronouns` của bộ luật (thay
/// Pronouns, cùng bộ lọc của `Config`) và danh xưng của nghĩa tên người (`personTitle`, dài nhất thắng); mọi đuôi ≥ 2 chữ
/// giữ phần thừa của `glued_fragment` (`isGlueKeep`). Bộ lọc **không** còn đọc Pronouns.
struct LocalNameFilterSetup {
    /// Cờ theo chữ, tra thẳng theo đơn vị UTF-16 ở vòng quét lượt 1.
    struct UnitFlags: OptionSet {
        let rawValue: UInt8
        static let surnameSingle = UnitFlags(rawValue: 1 << 0)
        static let surnamePairStart = UnitFlags(rawValue: 1 << 1)
        /// Đuôi 1 chữ loại địa danh / tông môn.
        static let placeSuffix = UnitFlags(rawValue: 1 << 2)
        static let sectSuffix = UnitFlags(rawValue: 1 << 3)
        static let suffixPairStart = UnitFlags(rawValue: 1 << 4)
        /// `cfg.suffix_chars` của bộ luật: đuôi 1 chữ loại place / sect.
        static let suffixChar = UnitFlags(rawValue: 1 << 5)
        /// Chữ cuối của một danh xưng (`pronouns`) — chặn sớm `pronoun_tail`.
        static let pronounLast = UnitFlags(rawValue: 1 << 6)
    }

    /// Bit loại đuôi trong `pairSuffixKinds`.
    static let placeKindBit: UInt8 = 1
    static let sectKindBit: UInt8 = 2

    /// "Ít nhất N lần".
    let minCount: Int
    /// "Không phải name" (khớp nguyên cụm, so theo code point) — lọc ở đầu ra cho cả hàng bộ luật lẫn hàng LAC.
    let blockedWords: Set<LocalNameFilterWord>
    /// "Loại cần tìm" — lọc ở đầu ra.
    let categories: Set<LocalNameFilter.Category>
    /// Cờ `V3` của bộ luật: bật khi chạy cùng model LAC (bước hợp), tắt ở đường lùi "chỉ bộ luật".
    let rulesV3: Bool
    /// Họ kép (cặp hai chữ).
    let surnamePairs: Set<UInt32>
    /// Đuôi 2 chữ: cặp → `placeKindBit | sectKindBit`.
    let pairSuffixKinds: [UInt32: UInt8]
    /// `cfg.pronouns`: danh xưng dùng được của bộ luật → nghĩa đầu (giữ nguyên chữ) — dựng từ hậu tố Nhân danh của danh
    /// sách người dùng (L11), lọc như `Config` (≤ 3 chữ, 1 chữ chỉ chữ thân tộc…). Rỗng khi danh sách không có hậu tố
    /// Nhân danh.
    let pronouns: [LocalNameFilterTermKey: String]
    /// Phía LAC: mọi đuôi dò theo khoá code point — địa danh / tổ chức / thuật ngữ 1–2 chữ, Nhân danh 2–6 chữ.
    let lacSuffixes: [LocalNameFilterWord: LocalNameFilter.Suffix]
    /// Phía LAC: chữ của đuôi dò 1 chữ (`SUFFIX_CHARS` của `lacpipe.py`; hậu tố Nhân danh dò luôn ≥ 2 chữ).
    let lacSuffixChars: Set<UInt32>
    /// "Độ dài name" (L15) — lọc ở đầu ra.
    let minLength: Int
    let maxLength: Int?
    private let lacSuffixMaxLength: Int
    /// Danh sách người dùng, đuôi địa danh / tổ chức / thuật ngữ theo khoá — chỉ để ghép nghĩa.
    private let meaningSuffixes: [LocalNameFilterWord: LocalNameFilter.Suffix]
    /// Danh sách người dùng, hậu tố Nhân danh → nghĩa đầu — danh xưng của nghĩa tên người (`personTitle`).
    private let personSuffixes: [LocalNameFilterWord: String]
    private let personSuffixMaxLength: Int
    /// Mọi khoá ≥ 2 chữ của danh sách người dùng (mọi loại) — phần thừa của `glued_fragment` là một trong số này ⇒ giữ.
    private let glueKeepWords: Set<LocalNameFilterWord>
    private let unitFlags: [UInt8]

    /// `detectionSuffixes` mặc định là bộ cố định của app; truyền vào chỉ để thử.
    init(
        configuration: LocalNameFilter.Configuration,
        dictionaries: LocalNameFilterDictionaries,
        rulesV3: Bool,
        detectionSuffixes: [LocalNameFilter.Suffix] = LocalNameFilterSuffixStore.detectionSuffixes
    ) {
        var flags = [UInt8](repeating: 0, count: 65_536)
        func mark(_ unit: UInt16, _ flag: UnitFlags) { flags[Int(unit)] |= flag.rawValue }

        minCount = configuration.minCount
        blockedWords = Set(configuration.blockedTerms.map { LocalNameFilterWord($0) })
        categories = configuration.categories
        minLength = configuration.minLength
        maxLength = configuration.maxLength
        self.rulesV3 = rulesV3

        var pairs = Set<UInt32>()
        for term in dictionaries.surnames.keys {
            if term.count == 1 {
                mark(term[0], .surnameSingle)
            } else if term.count == 2 {
                mark(term[0], .surnamePairStart)
                pairs.insert(LocalNameFilterRules.pair(term[0], term[1]))
            }
        }
        surnamePairs = pairs

        // Phía LAC — `detectable()` của `lacpipe.py`: địa danh / tổ chức / thuật ngữ 1–2 code point, Nhân danh 2–6.
        var lacSuffixes: [LocalNameFilterWord: LocalNameFilter.Suffix] = [:]
        var lacSuffixChars = Set<UInt32>()
        for suffix in detectionSuffixes {
            let word = LocalNameFilterWord(suffix.key)
            let lengths = suffix.kind == .person
                ? LocalNameFilterRules.personSuffixMinLength...LocalNameFilterSuffixListParser.maxKeyLength
                : 1...LocalNameFilterRules.detectionSuffixMaxLength
            guard lengths.contains(word.count), lacSuffixes[word] == nil else { continue }
            lacSuffixes[word] = suffix
            if word.count == 1 { lacSuffixChars.insert(word[0]) }
        }
        self.lacSuffixes = lacSuffixes
        self.lacSuffixChars = lacSuffixChars
        lacSuffixMaxLength = lacSuffixes.keys.map(\.count).max() ?? 0

        // Danh sách người dùng nhận khoá 1–6 chữ (việc 7, 2026-11-27); chia theo loại (xem doc của type).
        var meaningSuffixes: [LocalNameFilterWord: LocalNameFilter.Suffix] = [:]
        var personSuffixes: [LocalNameFilterWord: String] = [:]
        var glueKeepWords = Set<LocalNameFilterWord>()
        for suffix in configuration.suffixes {
            let word = LocalNameFilterWord(suffix.key)
            guard (1...LocalNameFilterSuffixListParser.maxKeyLength).contains(word.count) else { continue }
            if word.count >= 2 { glueKeepWords.insert(word) }
            if suffix.kind == .person {
                if personSuffixes[word] == nil {
                    personSuffixes[word] = LocalNameFilterRules.firstReading(suffix.meaning) ?? suffix.key
                }
            } else if meaningSuffixes[word] == nil {
                meaningSuffixes[word] = suffix
            }
        }
        self.meaningSuffixes = meaningSuffixes
        self.personSuffixes = personSuffixes
        personSuffixMaxLength = personSuffixes.keys.map(\.count).max() ?? 0
        self.glueKeepWords = glueKeepWords

        // Bộ luật: chỉ place / sect (không term, không person), khoá phải là 1–2 chữ Hán của dải bộ luật.
        var places: [LocalNameFilterTermKey: LocalNameFilter.Suffix] = [:]
        var sects: [LocalNameFilterTermKey: LocalNameFilter.Suffix] = [:]
        var pairKinds: [UInt32: UInt8] = [:]
        for suffix in detectionSuffixes where suffix.kind == .place || suffix.kind == .sect {
            guard let term = LocalNameFilterTermKey(string: suffix.key), term.count <= 2 else { continue }
            let isPlace = suffix.kind == .place
            if isPlace {
                if places[term] == nil { places[term] = suffix }
            } else if sects[term] == nil {
                sects[term] = suffix
            }
            if term.count == 1 {
                mark(term[0], isPlace ? .placeSuffix : .sectSuffix)
                mark(term[0], .suffixChar)
            } else {
                mark(term[0], .suffixPairStart)
                pairKinds[LocalNameFilterRules.pair(term[0], term[1]), default: 0] |= isPlace ? Self.placeKindBit : Self.sectKindBit
            }
        }
        pairSuffixKinds = pairKinds

        // `Config.pronouns` (nay từ hậu tố Nhân danh của danh sách người dùng): bỏ khoá 1 chữ ngoài nhóm thân tộc; khoá
        // ≤ 3 chữ, không trùng đuôi dò place / sect hay 家 / 氏 / 族, không chứa hư từ, không phải 儿.
        var suffixAll = Set(places.keys).union(sects.keys)
        for unit in LocalNameFilterRules.familySuffixes.utf16 { suffixAll.insert(LocalNameFilterTermKey(unit: unit)) }
        var pronouns: [LocalNameFilterTermKey: String] = [:]
        for (word, meaning) in personSuffixes {
            guard let term = word.termKey else { continue }
            if term.count == 1 && !LocalNameFilterRules.has(term[0], .kinship) { continue }
            guard term.count <= LocalNameFilterRules.pronounMaxLength, !suffixAll.contains(term),
                  !term.units.contains(where: { LocalNameFilterRules.has($0, .function) }),
                  !(term.count == 1 && LocalNameFilterRules.has(term[0], .namePartTail)) else { continue }
            pronouns[term] = meaning
            mark(term.last, .pronounLast)
        }
        self.pronouns = pronouns
        unitFlags = flags
    }

    @inline(__always)
    func has(_ unit: UInt16, _ flag: UnitFlags) -> Bool {
        unitFlags[Int(unit)] & flag.rawValue != 0
    }

    /// `pronoun_tail(term, sl)`: danh xưng dài nhất ở cuối phần tên (sau họ `surnameLength` chữ), không có ⇒ `nil`.
    func pronounTail(of term: LocalNameFilterTermKey, surnameLength: Int) -> LocalNameFilterTermKey? {
        let givenLength = term.count - surnameLength
        guard givenLength > 0, has(term.last, .pronounLast) else { return nil }
        for length in stride(from: min(3, givenLength), through: 1, by: -1) {
            if let tail = term.suffix(length), pronouns[tail] != nil { return tail }
        }
        return nil
    }

    /// `title_of(w, sl)` của `lacpipe.py` — danh xưng cuối của **nghĩa** tên người (L11): hậu tố Nhân danh **dài nhất**
    /// (6 … 2 chữ) của danh sách người dùng nằm trong phần sau họ (`surnameLength` chữ), phần trước còn ≥ 1 chữ (陈太上长老
    /// ⇒ 太上长老); không có ⇒ danh xưng 1 chữ đã qua chốt của bộ luật (`titles`: chữ thân tộc đứng sau ≥ 3 tên khác nhau).
    /// Trả khoá + nghĩa đầu; `nil` = không có danh xưng.
    func personTitle(
        of word: LocalNameFilterWord,
        surnameLength: Int,
        titles: Set<LocalNameFilterTermKey>
    ) -> (key: LocalNameFilterWord, meaning: String)? {
        let givenLength = word.count - surnameLength
        let longest = min(personSuffixMaxLength, givenLength, word.count - 1)
        if longest >= 2 {
            for length in stride(from: longest, through: 2, by: -1) {
                let tail = word.suffix(length)
                if let meaning = personSuffixes[tail] { return (tail, meaning) }
            }
        }
        if givenLength >= 1, word.count >= 2, let key = word.suffix(1).termKey, titles.contains(key),
           let meaning = pronouns[key] {
            return (word.suffix(1), meaning)
        }
        return nil
    }

    /// `rest in GLUE_KEEP` của `glued_fragment`: phần thừa là một khoá ≥ 2 chữ của danh sách người dùng, mọi loại (林砚|公子,
    /// 东阳|酒店).
    func isGlueKeep(_ word: LocalNameFilterWord) -> Bool {
        word.count >= 2 && glueKeepWords.contains(word)
    }

    /// Đuôi `key` trong danh sách người dùng (địa danh / tổ chức / thuật ngữ — nghĩa + vị trí), `nil` = người dùng đã xoá /
    /// không có.
    func meaningSuffix(_ key: LocalNameFilterWord) -> LocalNameFilter.Suffix? {
        meaningSuffixes[key]
    }

    /// `suffix_of` của `name_meaning.py`: đuôi địa danh / tổ chức / thuật ngữ dài nhất (6 … 1 chữ) của danh sách người dùng
    /// mà từ dài hơn đuôi — phần tên riêng còn ≥ 1 chữ (安保公司 thắng 公司).
    func meaningSuffix(of word: LocalNameFilterWord) -> (length: Int, suffix: LocalNameFilter.Suffix)? {
        for length in stride(from: LocalNameFilterSuffixListParser.maxKeyLength, through: 1, by: -1)
        where word.count > length {
            if let suffix = meaningSuffixes[word.suffix(length)] { return (length, suffix) }
        }
        return nil
    }

    /// `suffix_of(w)` của `lacpipe.py`: đuôi dò dài nhất (6 … 1 chữ, gồm hậu tố Nhân danh) mà từ dài hơn đuôi — chỉ để
    /// phân loại. Không có ⇒ `nil`.
    func lacSuffix(of word: LocalNameFilterWord) -> (length: Int, suffix: LocalNameFilter.Suffix)? {
        guard lacSuffixMaxLength > 0 else { return nil }
        for length in stride(from: lacSuffixMaxLength, through: 1, by: -1) where word.count > length {
            if let suffix = lacSuffixes[word.suffix(length)] { return (length, suffix) }
        }
        return nil
    }

    /// `suffix_of(w, RESCUE_ORDER)` của luật (e): như `lacSuffix` nhưng bỏ hậu tố Nhân danh (2 rồi 1 chữ).
    func lacRescueSuffix(of word: LocalNameFilterWord) -> (length: Int, suffix: LocalNameFilter.Suffix)? {
        for length in stride(from: LocalNameFilterRules.detectionSuffixMaxLength, through: 1, by: -1)
        where word.count > length {
            if let suffix = lacSuffixes[word.suffix(length)], suffix.kind != .person { return (length, suffix) }
        }
        return nil
    }
}
