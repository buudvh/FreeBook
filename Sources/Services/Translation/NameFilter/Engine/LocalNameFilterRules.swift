import Foundation

/// Hằng số và bảng chữ của bộ lọc name local — chép nguyên từ bản thử Python `local_name_filter2.py` (bộ luật) và
/// `lacpipe.py` (phía LAC), thư mục `Docs/Plans/local-name-filter-lac/`. Ba cờ của bộ luật cố định ở giá trị anh Bửu
/// duyệt: `STRICT_TAIL = True`, `GLUE_SUFFIX = True`, `TITLE_MODE = "combine"`; cờ `V3` bật khi có model LAC
/// (`LocalNameFilterSetup.rulesV3`), tắt ở đường lùi "chỉ bộ luật" (= bộ luật trước bản LAC).
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
    /// `NAME_PART_TAILS` — chữ có trong danh sách danh xưng (hậu tố Nhân danh) nhưng là phần của tên (王冬儿).
    static let namePartTails = "儿"
    /// `PERSON_AFTER` — chữ đứng sau tên người (đã bỏ qua danh xưng): `tail.startswith(p)`.
    static let personAfter = ["说道", "笑道", "问道", "喝道", "怒道", "冷笑", "冷哼", "沉声", "淡淡", "轻声", "点头", "摇头",
                              "皱眉", "开口", "说", "道", "问", "笑", "叹"]

    // MARK: - Tập chữ của luật v3 (Python, cờ `V3`)

    /// `GIVEN_BAD` — chữ thời gian / hướng / trợ từ không nằm trong phần tên người (东海时, 印生去, 石塔前).
    static let givenBad = "到前去后尽所时"
    /// `PLACE_INNER_BAD` — không nằm trong phần trước đuôi địa danh (宽阔如岛, 妾身所观).
    static let placeInnerBad = "似前后如所时般"
    /// `NUMERALS` — phần trước đuôi chỉ là một chữ số ⇒ không phải tên chỗ.
    static let numerals = "一七万三两九二五八六几十千四数百"
    /// `HEAD_LIGHT` — tên + chữ nhẹ (苏笙|笑, 法脉|中).
    static let headLight = "上下中冷前去叫叹后听喝开怒想摇时来沉淡点皱看笑说轻道里问"

    // MARK: - Tập chữ của phía LAC (`lacpipe.py`)

    /// `FUNCTION_CHARS` của `lacpipe.py` = hư từ của bộ luật bỏ 道 一 (74 chữ).
    static let lacFunctionChars = "不与个为么也了于些从他以们会但你便其再却又及只各向吗吧呀呢和哈哦啊嘛在地她它对将就已很得您我或才把敢於是有此每没的着给而能自被要让该说过还这连那都问"
    /// `TRAIL_LIGHT` — chữ nhẹ dính sau thực thể LAC (穆小鱼|道), bóc tối đa 2 chữ.
    static let trailLight = "上下中也便前却去又叹后就已时来正笑说道都里问"

    // MARK: - Phân loại phía LAC (plan 2026-11-27-phan-loai-name, `lacpipe.py` › `classify`)
    //
    // Tra theo code point (từ LAC dài tuỳ ý, có thể có chữ ngoài BMP) — không chiếm bit của `CharClass`.

    /// `LAC_WEAK_SUFFIX` = `weakSuffixChars` + 卫 泽 (L1 / L6): đuôi yếu **chỉ khi phân loại phía LAC** (王精卫, 李泽). Bộ
    /// luật và luật (e) giữ `weakSuffixChars`.
    static let lacWeakSuffixScalars: Set<UInt32> = scalarSet(weakSuffixChars + "卫泽")
    /// `CREATURE_CHARS` (L3): chữ cuối là loài vật / yêu ma (蜃龙, 啸月银狼, 赤炎魔).
    static let creatureScalars: Set<UInt32> = scalarSet("龙狼熊虎猿豹狮蛟蛇鹰雕鹏蝠蝎蛛鼠狐猴鹿鳄蟾鸦枭鹤凤凰麟兕魈蜥妖魔")
    /// `CREATURE_KEEP_START` (L3): mở đầu bằng 阿 / 小 ⇒ vẫn là người.
    static let creatureKeepStartScalars: Set<UInt32> = scalarSet("阿小")
    /// `COMMON_KEEP_START` / `COMMON_KEEP_END` (L4).
    static let commonKeepStartScalars: Set<UInt32> = scalarSet("小阿老")
    static let commonKeepEndScalars: Set<UInt32> = scalarSet("儿子")
    /// `RANK_PREFIX` (L5) = `^[一二三四五六七八九十百千万两零]+[阶级品]` — khác `numerals` (có 零, không có 几 数).
    static let rankNumeralScalars: Set<UInt32> = scalarSet("一二三四五六七八九十百千万两零")
    static let rankUnitScalars: Set<UInt32> = scalarSet("阶级品")
    /// L4: nhãn thường ≥ 2 lần tổng nhãn thực thể.
    static let commonTagFactor: Int32 = 2

    // MARK: - Ngưỡng (Python)

    static let dominance = 0.6
    static let lightDominance = 0.9
    static let glue = 0.5
    static let commonPartRatio = 1.5
    static let containedRatio = 3.0
    /// Danh xưng 1 chữ: phải đứng sau ≥ 3 tên / họ khác nhau trong truyện.
    static let titleMinPredecessors = 3
    /// v3 `WEAK_SURNAME`: họ dính vào từ thường ≥ 60 % số lần ⇒ cần bằng chứng là tên người.
    static let weakSurname = 0.6
    /// v3 `SPEECH_MIN_RATIO` + hai ngưỡng bằng chứng còn lại (danh xưng theo sau, đứng đầu vế câu).
    static let speechMinRatio = 0.02
    static let titleAfterRatio = 0.1
    static let clauseStartRatio = 0.3
    /// Phía LAC: tên + 1 chữ gộp về tên khi phần tên mạnh ≥ 5 lần (李印生|盘).
    static let lacHeadStrength: Int32 = 5
    /// Phía LAC: mảnh nằm trong cụm dài ≥ 60 % số lần ⇒ mảnh.
    static let lacFragmentRatio = 0.6
    /// Phía LAC (`glued_fragment`): thực thể bên trong mạnh ≥ 3 lần cụm.
    static let lacGlueStrength = 3
    /// `Config.pronouns` (danh xưng của bộ luật, nay dựng từ hậu tố Nhân danh) chỉ nhận khoá ≤ 3 chữ.
    static let pronounMaxLength = 3
    /// `detectable()` của `lacpipe.py`: hậu tố Nhân danh dò ở phía LAC dài 2–6 chữ; đuôi địa danh / tổ chức / thuật ngữ
    /// 1–2 chữ.
    static let personSuffixMinLength = 2
    static let detectionSuffixMaxLength = 2

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
        // v3
        static let personHeadPlusLight = "person_head_plus_light"
        static let weakSurnameNoEvidence = "weak_surname_no_evidence"
        // Phía LAC (`lacpipe.py`). `dict_common_word` / `dict_common_head` / `dict_common_given` trùng tên luật của bộ
        // luật nhưng là luật riêng của phía LAC — log tách hai nhóm.
        static let fragment = "fragment"
        static let minCount = "min_count"
        static let functionChar = "function_char"
        static let gluedFragment = "glued_fragment"
        /// L5: số + 阶 / 级 / 品 ở đầu (九阶妖王) — phía LAC (cả name đã có) và hàng bộ luật ở bước hợp.
        static let rankPrefix = "rank_prefix"
        /// L9: hai tên người của danh sách dính liền (姬晴|苟义), name chưa có.
        static let gluedNames = "glued_names"
        /// Đầu ra: ngoài "Loại cần tìm".
        static let categoryOff = "category_off"
        /// Đầu ra (L15): ngoài "Độ dài name".
        static let lengthOff = "length_off"
    }

    // MARK: - Loại ứng viên

    /// `KIND_ORDER` của Python: place 0, sect 1, family 2, person 3 — các loại **bộ luật** sinh ứng viên. `term` chỉ có ở
    /// phía LAC (thực thể `nz` / `nw` hoặc đuôi loại `term`), không bao giờ là ứng viên của bộ luật.
    static let kindOrder: [LocalNameFilter.Kind] = [.place, .sect, .family, .person]
    static let placeOrder = 0
    static let sectOrder = 1
    static let familyOrder = 2
    static let personOrder = 3

    /// Một cặp `(kind, extra)` của Python thành một bit: `extra` là độ dài họ (person / family) hoặc độ dài đuôi
    /// (place / sect), luôn 1 hoặc 2 ⇒ 4 loại × 2 = 8 bit.
    static func kindBit(order: Int, extra: Int) -> UInt8 {
        UInt8(1) << UInt8(order * 2 + (extra - 1))
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
        static let givenBad = CharClass(rawValue: 1 << 9)
        static let placeInnerBad = CharClass(rawValue: 1 << 10)
        static let numeral = CharClass(rawValue: 1 << 11)
        static let headLight = CharClass(rawValue: 1 << 12)
        static let lacFunction = CharClass(rawValue: 1 << 13)
        static let trailLight = CharClass(rawValue: 1 << 14)
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
        mark(givenBad, .givenBad)
        mark(placeInnerBad, .placeInnerBad)
        mark(numerals, .numeral)
        mark(headLight, .headLight)
        mark(lacFunctionChars, .lacFunction)
        mark(trailLight, .trailLight)
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

    /// `has` theo code point (phía LAC): chữ ngoài BMP không thuộc tập nào.
    @inline(__always)
    static func has(scalar: UInt32, _ cls: CharClass) -> Bool {
        scalar <= 0xFFFF && has(UInt16(scalar), cls)
    }

    /// Dải chữ Hán của `HAN_RUN` trong Python: `[㐀-䶿一-鿿豈-﫿]`.
    @inline(__always)
    static func isHan(_ unit: UInt16) -> Bool {
        (0x4E00...0x9FFF).contains(unit) || (0x3400...0x4DBF).contains(unit) || (0xF900...0xFAFF).contains(unit)
    }

    /// Dải `HAN` của `lacpipe.py` (U+3400–9FFF, U+F900–FAFF): từ LAC phải có ít nhất một chữ trong dải này.
    @inline(__always)
    static func isLACHan(_ scalar: UInt32) -> Bool {
        (0x3400...0x9FFF).contains(scalar) || (0xF900...0xFAFF).contains(scalar)
    }

    @inline(__always)
    static func pair(_ first: UInt16, _ second: UInt16) -> UInt32 {
        UInt32(first) << 16 | UInt32(second)
    }

    /// L5 `RANK_PREFIX.match(w)`: một hay nhiều chữ số rồi 阶 / 级 / 品 (九阶, 八级定装魂导炮弹).
    static func isRankPrefix(_ word: LocalNameFilterWord) -> Bool {
        var index = 0
        while index < word.count, rankNumeralScalars.contains(word[index]) { index += 1 }
        return index > 0 && index < word.count && rankUnitScalars.contains(word[index])
    }

    /// `name_length(w)` của `lacpipe.py` (L15): số chữ (code point), không tính dấu `·` (U+00B7).
    static func nameLength(_ word: LocalNameFilterWord) -> Int {
        word.scalars.reduce(0) { $0 + ($1 == 0x00B7 ? 0 : 1) }
    }

    private static func scalarSet(_ chars: String) -> Set<UInt32> {
        Set(chars.unicodeScalars.map(\.value))
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
            .map { word in word.prefix(1).uppercased() + String(word.dropFirst()) }
            .joined(separator: " ")
    }
}
