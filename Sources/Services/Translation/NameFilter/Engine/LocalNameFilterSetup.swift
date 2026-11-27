import Foundation

/// Bảng tra dựng **một** lần mỗi lượt lọc từ `LocalNameFilter.Configuration` + bản chụp từ điển — phần `Config` của bản
/// thử Python (`local_name_filter2.py`), với đuôi lấy từ `Configuration.suffixes` thay cho `DEFAULT_PLACE` /
/// `DEFAULT_SECT` + extra. Bất biến sau khi dựng.
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
        /// `cfg.suffix_chars`: đuôi 1 chữ (mọi loại).
        static let suffixChar = UnitFlags(rawValue: 1 << 5)
        /// Chữ cuối của một danh xưng (`pronouns`) — chặn sớm `pronoun_tail`.
        static let pronounLast = UnitFlags(rawValue: 1 << 6)
    }

    /// Bit loại đuôi trong `pairSuffixKinds`.
    static let placeKindBit: UInt8 = 1
    static let sectKindBit: UInt8 = 2

    /// "Ít nhất N lần".
    let minCount: Int
    /// "Không phải name" (khớp nguyên cụm). Cụm không phải 1–5 chữ Hán không bao giờ là name ⇒ bỏ khi dựng.
    let blockedTerms: Set<LocalNameFilterTermKey>
    /// Họ kép (cặp hai chữ).
    let surnamePairs: Set<UInt32>
    /// Đuôi 2 chữ: cặp → `placeKindBit | sectKindBit`.
    let pairSuffixKinds: [UInt32: UInt8]
    /// `cfg.pronouns`: danh xưng dùng được → nghĩa đầu trong từ điển Đại từ (giữ nguyên chữ). Rỗng khi chưa nạp Pronouns.
    let pronouns: [LocalNameFilterTermKey: String]
    /// Đuôi đang bật theo loại (nghĩa + vị trí).
    private let placeSuffixes: [LocalNameFilterTermKey: LocalNameFilter.Suffix]
    private let sectSuffixes: [LocalNameFilterTermKey: LocalNameFilter.Suffix]
    private let unitFlags: [UInt8]

    init(configuration: LocalNameFilter.Configuration, dictionaries: LocalNameFilterDictionaries) {
        var flags = [UInt8](repeating: 0, count: 65_536)
        func mark(_ unit: UInt16, _ flag: UnitFlags) { flags[Int(unit)] |= flag.rawValue }

        minCount = configuration.minCount
        blockedTerms = Set(configuration.blockedTerms.compactMap { LocalNameFilterTermKey(string: $0) })

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

        // Đuôi: khoá phải là 1–2 chữ Hán (Phần B đã kiểm; khoá khác bỏ qua cho chắc).
        var places: [LocalNameFilterTermKey: LocalNameFilter.Suffix] = [:]
        var sects: [LocalNameFilterTermKey: LocalNameFilter.Suffix] = [:]
        var pairKinds: [UInt32: UInt8] = [:]
        for suffix in configuration.suffixes {
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
        placeSuffixes = places
        sectSuffixes = sects
        pairSuffixKinds = pairKinds

        // `Config.pronouns`: bỏ khoá 1 chữ ngoài nhóm thân tộc; khoá ≤ 3 chữ, không trùng đuôi đang bật hay 家 / 氏 / 族,
        // không chứa hư từ, không phải 儿.
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

    /// Nghĩa + vị trí của đuôi `suffix` cho một name loại `kind` (place / sect). Python tra theo khoá đuôi; ở đây ưu tiên
    /// đuôi cùng loại, rồi tới loại kia nếu người dùng khai cùng khoá ở cả hai loại.
    func suffixMeaning(_ suffix: LocalNameFilterTermKey, kind: LocalNameFilter.Kind) -> LocalNameFilter.Suffix? {
        kind == .sect
            ? (sectSuffixes[suffix] ?? placeSuffixes[suffix])
            : (placeSuffixes[suffix] ?? sectSuffixes[suffix])
    }
}
