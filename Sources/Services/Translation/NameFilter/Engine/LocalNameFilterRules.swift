import Foundation

/// Hằng số và bảng chữ của bộ lọc name local — chép nguyên từ bản thử Python `local_name_filter2.py`
/// (`Docs/Plans/local-name-filter/`). Ba cờ của bản thử cố định ở giá trị anh Bửu duyệt: `STRICT_TAIL = True`,
/// `GLUE_SUFFIX = True`, `TITLE_MODE = "combine"` — các nhánh còn lại của Python không được chép.
///
/// Các tập chữ dưới đây là tập của Python **đã sắp lại** (sinh bằng script từ file `.py`, đã so số phần tử). Đơn vị là
/// UTF-16: cả ba dải Hán bộ lọc xét (`U+3400–4DBF`, `U+4E00–9FFF`, `U+F900–FAFF`) đều nằm trong BMP nên một đơn vị =
/// một code point = một chỉ số chuỗi của Python.
enum LocalNameFilterRules {
    // MARK: - Tập chữ (Python)

    /// `FUNCTION_CHARS` — hư từ (76 chữ).
    static let functionChars = "一不与个为么也了于些从他以们会但你便其再却又及只各向吗吧呀呢和哈哦啊嘛在地她它对将就已很得您我或才把敢於是有此每没的着给而能自被要让该说过还这连道那都问"
    /// `PLACE_BAD_START` = hư từ + 28 chữ này (104 chữ).
    static let placeBadStartExtra = "上下中人入全内出到前去后回外大小往整来某次比满片离至进里"
    /// `RIGHT_LIGHT` = hư từ + 15 chữ này (91 chữ).
    static let rightLightExtra = "冷叫听喝开怒想摇沉淡点皱看笑轻"
    /// `LOCATIVE_BEFORE` (12 chữ).
    static let locativeBefore = "于从入出到去回在往离至进"
    /// `WEAK_SUFFIX_CHARS` (14 chữ).
    static let weakSuffixChars = "原城堂宫山岭峰崖楼江河海渊湖"
    /// `FAMILY_SUFFIXES`: họ + 家 / 氏 / 族.
    static let familySuffixes = "家氏族"
    /// `KINSHIP_TAILS` — danh xưng 1 chữ chỉ lấy trong nhóm thân tộc / kính xưng này (18 chữ).
    static let kinshipTails = "伯兄公叔哥妹姐姑姨婶嫂少弟母父爷老舅"
    /// `NAME_PART_TAILS` — chữ có trong từ điển Đại từ nhưng là phần của tên (王冬儿).
    static let namePartTails = "儿"
    /// `PERSON_AFTER` — chữ đứng sau tên người (đã bỏ qua danh xưng): `tail.startswith(p)`.
    static let personAfter = ["说道", "笑道", "问道", "喝道", "怒道", "冷笑", "冷哼", "沉声", "淡淡", "轻声", "点头", "摇头",
                              "皱眉", "开口", "说", "道", "问", "笑", "叹"]

    // MARK: - Ngưỡng (Python)

    static let dominance = 0.6
    static let lightDominance = 0.9
    static let glue = 0.5
    static let commonPartRatio = 1.5
    static let containedRatio = 3.0
    /// Danh xưng 1 chữ: phải đứng sau ≥ 3 tên / họ khác nhau trong truyện.
    static let titleMinPredecessors = 3
    /// `Config.pronouns` chỉ nhận khoá ≤ 3 chữ.
    static let pronounMaxLength = 3

    // MARK: - Lý do bỏ (đúng chuỗi Python)

    enum Reason {
        static let shapeFunctionChar = "shape_function_char"
        static let shapePlaceStart = "shape_place_start"
        static let glueLeft = "glue_left"
        static let dictCommonHead = "dict_common_head"
        static let dictCommonGiven = "dict_common_given"
        static let dictCommonTail = "dict_common_tail"
        static let glueRight = "glue_right"
        static let containedKnownTail = "contained_known_tail"
        static let boundRight = "bound_right"
        static let boundLeft = "bound_left"
        static let dictCommonWord = "dict_common_word"
        static let userBlocked = "user_blocked"
    }

    // MARK: - Loại ứng viên

    /// `KIND_ORDER` của Python: place 0, sect 1, family 2, person 3.
    static let kindOrder: [LocalNameFilter.Kind] = [.place, .sect, .family, .person]

    /// Một cặp `(kind, extra)` của Python thành một bit: `extra` là độ dài họ (person / family) hoặc độ dài đuôi
    /// (place / sect), luôn 1 hoặc 2 ⇒ 4 loại × 2 = 8 bit.
    static func kindBit(order: Int, extra: Int) -> UInt8 {
        UInt8(1) << UInt8(order * 2 + (extra - 1))
    }

    static func order(of kind: LocalNameFilter.Kind) -> Int {
        switch kind {
        case .place: return 0
        case .sect: return 1
        case .family: return 2
        case .person: return 3
        }
    }

    // MARK: - Bảng tra theo chữ

    struct CharClass: OptionSet {
        let rawValue: UInt16
        static let function = CharClass(rawValue: 1 << 0)
        static let placeBadStart = CharClass(rawValue: 1 << 1)
        static let rightLight = CharClass(rawValue: 1 << 2)
        static let locative = CharClass(rawValue: 1 << 3)
        static let weakSuffix = CharClass(rawValue: 1 << 4)
        static let family = CharClass(rawValue: 1 << 5)
        static let kinship = CharClass(rawValue: 1 << 6)
        static let namePartTail = CharClass(rawValue: 1 << 7)
        /// Chữ đơn của `PERSON_AFTER` (说 道 问 笑 叹).
        static let personAfterSingle = CharClass(rawValue: 1 << 8)
    }

    /// 65.536 ô, tra thẳng theo đơn vị UTF-16 — vòng quét không băm.
    private static let classTable: [UInt16] = {
        var table = [UInt16](repeating: 0, count: 65_536)
        func mark(_ chars: String, _ cls: CharClass) {
            for unit in chars.utf16 { table[Int(unit)] |= cls.rawValue }
        }
        mark(functionChars, [.function, .placeBadStart, .rightLight])
        mark(placeBadStartExtra, .placeBadStart)
        mark(rightLightExtra, .rightLight)
        mark(locativeBefore, .locative)
        mark(weakSuffixChars, .weakSuffix)
        mark(familySuffixes, .family)
        mark(kinshipTails, .kinship)
        mark(namePartTails, .namePartTail)
        for word in personAfter where word.utf16.count == 1 { mark(word, .personAfterSingle) }
        return table
    }()

    /// Hai chữ của `PERSON_AFTER` dạng cặp (`pair`).
    static let personAfterPairs: Set<UInt32> = Set(personAfter.compactMap { word in
        let units = Array(word.utf16)
        return units.count == 2 ? pair(units[0], units[1]) : nil
    })

    @inline(__always)
    static func charClass(_ unit: UInt16) -> CharClass {
        CharClass(rawValue: classTable[Int(unit)])
    }

    @inline(__always)
    static func has(_ unit: UInt16, _ cls: CharClass) -> Bool {
        classTable[Int(unit)] & cls.rawValue != 0
    }

    /// Dải chữ Hán của `HAN_RUN` trong Python: `[㐀-䶿一-鿿豈-﫿]`.
    @inline(__always)
    static func isHan(_ unit: UInt16) -> Bool {
        (0x4E00...0x9FFF).contains(unit) || (0x3400...0x4DBF).contains(unit) || (0xF900...0xFAFF).contains(unit)
    }

    @inline(__always)
    static func pair(_ first: UInt16, _ second: UInt16) -> UInt32 {
        UInt32(first) << 16 | UInt32(second)
    }

    /// `readings(v)[0]` của Python: tách theo `/ | ;`, bỏ khoảng trắng hai đầu, lấy mảnh **không rỗng** đầu tiên.
    static func firstReading(_ value: String) -> String? {
        for piece in value.split(whereSeparator: { $0 == "/" || $0 == "|" || $0 == ";" }) {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// `cap_words` của Python: tách theo khoảng trắng (gộp khoảng trắng liền), viết hoa chữ đầu mỗi từ, nối bằng một dấu cách.
    static func capitalizeWords(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
    }
}
