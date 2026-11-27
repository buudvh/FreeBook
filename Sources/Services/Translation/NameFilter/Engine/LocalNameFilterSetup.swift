import Foundation

/// Bảng tra dựng **một** lần mỗi lượt lọc từ `LocalNameFilter.Configuration` + bản chụp từ điển — phần `Config` của bản
/// thử Python (`local_name_filter2.py` + `lacpipe.py`). Bất biến sau khi dựng.
///
/// Đuôi (cách A, 2026-11-27, anh Bửu): **dò** dùng bộ cố định `detectionSuffixes` = file gốc `NameFilterSuffixes.txt` trừ
/// dòng `|off` (`LocalNameFilterSuffixStore.detectionSuffixes`), **không** theo danh sách người dùng — cấu hình mặc định
/// cho đúng số liệu như trước. Bộ dò chia hai đường như Python:
/// - **bộ luật** chỉ thấy đuôi `place` / `sect` (sinh ứng viên, `suffix_chars`, lọc danh xưng) — đuôi `term` không bao
///   giờ sinh ứng viên;
/// - **phía LAC** thấy mọi đuôi dò (`SUFFIXES` của `lacpipe.py`): phân loại thực thể, luật "tên + 1 chữ", chữ cuối gom
///   số "nhãn khác" của bộ gắn nhãn.
/// Danh sách người dùng (`Configuration.suffixes`, mọi đuôi) **chỉ** để ghép nghĩa (`meaningSuffix`).
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
    /// `cfg.pronouns`: danh xưng dùng được → nghĩa đầu trong từ điển Đại từ (giữ nguyên chữ). Rỗng khi chưa nạp Pronouns.
    let pronouns: [LocalNameFilterTermKey: String]
    /// Phía LAC: mọi đuôi dò (place / sect / term) theo khoá code point.
    let lacSuffixes: [LocalNameFilterWord: LocalNameFilter.Suffix]
    /// Phía LAC: chữ của đuôi dò 1 chữ, mọi loại (`SUFFIX_CHARS` của `lacpipe.py`).
    let lacSuffixChars: Set<UInt32>
    /// Danh sách người dùng (mọi đuôi) theo khoá — chỉ để ghép nghĩa.
    private let meaningSuffixes: [LocalNameFilterWord: LocalNameFilter.Suffix]
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

        // Phía LAC: mọi đuôi dò, khoá 1–2 code point (Phần danh sách đã kiểm; khoá khác bỏ qua cho chắc).
        var lacSuffixes: [LocalNameFilterWord: LocalNameFilter.Suffix] = [:]
        var lacSuffixChars = Set<UInt32>()
        for suffix in detectionSuffixes {
            let word = LocalNameFilterWord(suffix.key)
            guard (1...2).contains(word.count), lacSuffixes[word] == nil else { continue }
            lacSuffixes[word] = suffix
            if word.count == 1 { lacSuffixChars.insert(word[0]) }
        }
        self.lacSuffixes = lacSuffixes
        self.lacSuffixChars = lacSuffixChars

        var meaningSuffixes: [LocalNameFilterWord: LocalNameFilter.Suffix] = [:]
        for suffix in configuration.suffixes {
            let word = LocalNameFilterWord(suffix.key)
            guard (1...2).contains(word.count), meaningSuffixes[word] == nil else { continue }
            meaningSuffixes[word] = suffix
        }
        self.meaningSuffixes = meaningSuffixes

        // Bộ luật: chỉ place / sect, khoá phải là 1–2 chữ Hán của dải bộ luật.
        var places: [LocalNameFilterTermKey: LocalNameFilter.Suffix] = [:]
        var sects: [LocalNameFilterTermKey: LocalNameFilter.Suffix] = [:]
        var pairKinds: [UInt32: UInt8] = [:]
        for suffix in detectionSuffixes where suffix.kind != .term {
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

        // `Config.pronouns`: bỏ khoá 1 chữ ngoài nhóm thân tộc; khoá ≤ 3 chữ, không trùng đuôi dò place / sect hay
        // 家 / 氏 / 族, không chứa hư từ, không phải 儿.
        var suffixAll = Set(places.keys).union(sects.keys)
        for unit in LocalNameFilterRules.familySuffixes.utf16 { suffixAll.insert(LocalNameFilterTermKey(unit: unit)) }
        var pronouns: [LocalNameFilterTermKey: String] = [:]
        for (term, meaning) in dictionaries.pronounEntries ?? [:] {
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

    /// `pronoun_tail` cho từ phía LAC (dài tuỳ ý): xét 3, 2, 1 chữ cuối của phần sau họ.
    func pronounTail(of word: LocalNameFilterWord, surnameLength: Int) -> LocalNameFilterTermKey? {
        let givenLength = word.count - surnameLength
        guard givenLength > 0, word.last <= 0xFFFF, has(UInt16(word.last), .pronounLast) else { return nil }
        for length in stride(from: min(3, givenLength), through: 1, by: -1) {
            if let tail = word.suffix(length).termKey, pronouns[tail] != nil { return tail }
        }
        return nil
    }

    /// Đuôi `key` trong danh sách người dùng (nghĩa + vị trí), `nil` = người dùng đã xoá / không có.
    func meaningSuffix(_ key: LocalNameFilterWord) -> LocalNameFilter.Suffix? {
        meaningSuffixes[key]
    }

    /// `suffix_of` của `name_meaning.py`: đuôi dài nhất (2 rồi 1 chữ) của danh sách người dùng mà từ dài hơn đuôi.
    func meaningSuffix(of word: LocalNameFilterWord) -> (length: Int, suffix: LocalNameFilter.Suffix)? {
        for length in stride(from: 2, through: 1, by: -1) where word.count > length {
            if let suffix = meaningSuffixes[word.suffix(length)] { return (length, suffix) }
        }
        return nil
    }

    /// `suffix_of(w)` của `lacpipe.py`: đuôi dò dài nhất (2 rồi 1 chữ) mà từ dài hơn đuôi — chỉ để phân loại. Không
    /// có ⇒ `nil`.
    func lacSuffix(of word: LocalNameFilterWord) -> (length: Int, suffix: LocalNameFilter.Suffix)? {
        for length in stride(from: 2, through: 1, by: -1) where word.count > length {
            if let suffix = lacSuffixes[word.suffix(length)] { return (length, suffix) }
        }
        return nil
    }
}
