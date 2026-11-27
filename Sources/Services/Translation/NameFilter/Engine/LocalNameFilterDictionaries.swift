import Foundation

/// Bản chụp từ điển cho **một** lượt lọc name local — phần `Dicts` của bản thử Python, nhưng đọc từ các lớp từ điển thật
/// của app. Chụp một lần lúc bắt đầu (`capture`) từ `TranslationManager.shared`: các lớp là `FrozenTrieDictionary` bất biến,
/// đọc ngoài main được, nên sửa từ điển giữa chừng không đổi kết quả của lượt đang chạy.
///
/// - "Có trong VP" (luật glue, `in d.vp` của Python): khớp **trọn** chuỗi ở bất kỳ lớp VietPhrase nào — riêng truyện,
///   Chung đã sửa, gốc (bỏ từ đã xoá `deletedVietPhrase`) — như `AIBookDataInspector.checkWordInVietPhrase`.
/// - `status` (`Dicts.status`): có trong bất kỳ lớp Name nào (riêng / Chung / gốc trừ `deletedNames`) ⇒ `known`; không thì
///   nghĩa VP hiệu lực theo thứ tự riêng > Chung đã sửa > gốc, nghĩa đầu (`TranslateUtils.getFirstMeaning`) viết hoa chữ
///   đầu ⇒ `known`, còn lại ⇒ `common`; không có ⇒ `nil`.
/// - Phiên âm (`phienAmMap`), họ đang bật (`QuickTranslationSurnameStore`, bỏ họ chứa hư từ như Python). **Không** chụp
///   Pronouns (plan 2026-11-27-phan-loai-name L11, anh Bửu duyệt): danh xưng của bộ lọc lấy từ hậu tố Nhân danh của danh
///   sách hậu tố (`LocalNameFilterSetup`) — Pronouns là từ điển của bộ dịch, cắt cho vừa bộ lọc là hỏng bản dịch.
/// - Nghĩa thô cho nghĩa đề xuất (`dictionaryValue`, 2026-11-27): Name (riêng > Chung > gốc trừ đã xoá) rồi VP hiệu lực —
///   lớp đầu tiên có khoá thắng, như thứ tự dịch (Name đè VP).
///
/// Bộ nhớ đệm tra cứu **không khoá**: chỉ dùng trên task của lượt lọc. Mọi hàm tra là hàm thuần của bản chụp, nên nhớ qua
/// nhiều lần chụp kết quả vẫn đúng.
final class LocalNameFilterDictionaries {
    enum Status: UInt8 {
        case known = 1
        case common = 2
    }

    private let bookVietPhrase: FrozenTrieDictionary?
    private let customVietPhrase: FrozenTrieDictionary?
    private let baseVietPhrase: FrozenTrieDictionary
    private let deletedVietPhrase: Set<String>
    private let bookNames: FrozenTrieDictionary?
    private let customNames: FrozenTrieDictionary?
    private let baseNames: FrozenTrieDictionary?
    private let deletedNames: Set<String>
    private let phienAmMap: [String: String]

    /// Họ đang bật, bỏ họ có chữ thuộc `FUNCTION_CHARS`: khoá → âm đầu (`""` khi file không có âm).
    let surnames: [LocalNameFilterTermKey: String]

    /// `Status.rawValue`, 0 = không có trong VP / Name; vắng khoá = chưa tra.
    private var statusMemo: [LocalNameFilterTermKey: UInt8] = [:]
    /// Như `statusMemo` cho từ phía LAC không đổi được thành `LocalNameFilterTermKey` (dài > 5, có chữ ngoài dải Hán).
    private var wordStatusMemo: [LocalNameFilterWord: UInt8] = [:]
    private var vietPhrasePairMemo: [UInt32: Bool] = [:]
    private var phienAmMemo: [UInt32: String] = [:]

    private init(
        bookVietPhrase: FrozenTrieDictionary?, customVietPhrase: FrozenTrieDictionary?, baseVietPhrase: FrozenTrieDictionary,
        deletedVietPhrase: Set<String>, bookNames: FrozenTrieDictionary?, customNames: FrozenTrieDictionary?,
        baseNames: FrozenTrieDictionary?, deletedNames: Set<String>, phienAmMap: [String: String],
        surnames: [LocalNameFilterTermKey: String]
    ) {
        self.bookVietPhrase = bookVietPhrase
        self.customVietPhrase = customVietPhrase
        self.baseVietPhrase = baseVietPhrase
        self.deletedVietPhrase = deletedVietPhrase
        self.bookNames = bookNames
        self.customNames = customNames
        self.baseNames = baseNames
        self.deletedNames = deletedNames
        self.phienAmMap = phienAmMap
        self.surnames = surnames
    }

    // MARK: - Chụp

    /// `nil` ⇒ VietPhrase gốc chưa nạp (`vietPhraseDict == nil`), không lọc được.
    static func capture(bookId: String) -> LocalNameFilterDictionaries? {
        let manager = TranslationManager.shared
        guard let baseVietPhrase = manager.vietPhraseDict?.frozen() else { return nil }
        let book: (vietPhrase: TrieDictionary?, names: TrieDictionary?) = bookId.isEmpty
            ? (vietPhrase: nil, names: nil)
            : manager.getBookDictionaries(for: bookId)
        return LocalNameFilterDictionaries(
            bookVietPhrase: book.vietPhrase?.frozen(),
            customVietPhrase: manager.customVietPhraseDict?.frozen(),
            baseVietPhrase: baseVietPhrase,
            deletedVietPhrase: manager.deletedVietPhrase,
            bookNames: book.names?.frozen(),
            customNames: manager.customNamesDict?.frozen(),
            baseNames: manager.namesDict?.frozen(),
            deletedNames: manager.deletedNames,
            phienAmMap: manager.phienAmMap,
            surnames: surnameTable(QuickTranslationSurnameStore.shared.lookupTable())
        )
    }

    /// `Dicts.surnames` của Python: bỏ họ có hư từ, giữ âm đầu (`(readings(v) or [""])[0]`).
    private static func surnameTable(_ table: [String: String]) -> [LocalNameFilterTermKey: String] {
        var result: [LocalNameFilterTermKey: String] = [:]
        for (key, value) in table {
            guard let term = LocalNameFilterTermKey(string: key), term.count <= 2,
                  !term.units.contains(where: { LocalNameFilterRules.has($0, .function) }) else { continue }
            result[term] = LocalNameFilterRules.firstReading(value) ?? ""
        }
        return result
    }

    // MARK: - Tra

    /// `Dicts.status` (xem doc của type).
    func status(_ term: LocalNameFilterTermKey) -> Status? {
        if let cached = statusMemo[term] { return Status(rawValue: cached) }
        let result = lookupStatus(term.string)
        statusMemo[term] = result?.rawValue ?? 0
        return result
    }

    /// `status` cho từ phía LAC — cùng luật, từ đổi được thành cụm của bộ luật thì dùng chung bộ nhớ đệm. Từ rỗng ⇒ `nil`.
    func status(word: LocalNameFilterWord) -> Status? {
        if word.isEmpty { return nil }
        if let term = word.termKey { return status(term) }
        if let cached = wordStatusMemo[word] { return Status(rawValue: cached) }
        let result = lookupStatus(word.string)
        wordStatusMemo[word] = result?.rawValue ?? 0
        return result
    }

    private func lookupStatus(_ word: String) -> Status? {
        if containsName(word) { return .known }
        guard let raw = vietPhraseMeaning(word) else { return nil }
        let first = TranslateUtils.getFirstMeaning(of: raw)
        return first.first?.isUppercase == true ? .known : .common
    }

    /// `surname_len(w)` của `lacpipe.py`: họ kép khi từ ≥ 3 chữ, rồi họ đơn khi từ ≥ 2 chữ, không có ⇒ 0. "Mở đầu bằng họ"
    /// của luật phân loại phía LAC (L1–L4) = kết quả > 0.
    func surnameLength(of word: LocalNameFilterWord) -> Int {
        if word.count >= 3, let key = word.slice(0, 2).termKey, surnames[key] != nil { return 2 }
        if word.count >= 2, let key = word.slice(0, 1).termKey, surnames[key] != nil { return 1 }
        return 0
    }

    /// `run[a:b] in d.vp` cho cặp hai chữ (luật `glue_left` / `glue_right`).
    func containsVietPhrase(_ first: UInt16, _ second: UInt16) -> Bool {
        let key = LocalNameFilterRules.pair(first, second)
        if let cached = vietPhrasePairMemo[key] { return cached }
        let found = vietPhraseMeaning(String(decoding: [first, second], as: UTF16.self)) != nil
        vietPhrasePairMemo[key] = found
        return found
    }

    /// `d.phienam.get(c, c)`: âm Hán-Việt đầu của một chữ, không có ⇒ chính chữ đó.
    func phienAm(_ unit: UInt16) -> String {
        phienAm(scalar: UInt32(unit))
    }

    /// `phienAm` theo code point (phía LAC: chữ khối mở rộng, dấu `·`…).
    func phienAm(scalar value: UInt32) -> String {
        if let cached = phienAmMemo[value] { return cached }
        guard let scalar = Unicode.Scalar(value) else { return "" }
        let char = String(Character(scalar))
        let reading = phienAmMap[char].flatMap(LocalNameFilterRules.firstReading) ?? char
        phienAmMemo[value] = reading
        return reading
    }

    /// Nghĩa thô của `word` (khớp trọn) để dựng nghĩa đề xuất: Name riêng > Name Chung > Name gốc (trừ đã xoá), rồi VP
    /// hiệu lực. `nil` = không có ở lớp nào.
    func dictionaryValue(_ word: String) -> String? {
        if let value = Self.exactValue(bookNames, word) { return value }
        if let value = Self.exactValue(customNames, word) { return value }
        if !deletedNames.contains(word), let value = Self.exactValue(baseNames, word) { return value }
        return vietPhraseMeaning(word)
    }

    /// Nghĩa VP hiệu lực của `word` (khớp trọn): riêng truyện > Chung đã sửa > gốc (trừ từ đã xoá).
    private func vietPhraseMeaning(_ word: String) -> String? {
        if let value = Self.exactValue(bookVietPhrase, word) { return value }
        if let value = Self.exactValue(customVietPhrase, word) { return value }
        guard !deletedVietPhrase.contains(word) else { return nil }
        return Self.exactValue(baseVietPhrase, word)
    }

    private func containsName(_ word: String) -> Bool {
        if Self.exactValue(bookNames, word) != nil { return true }
        if Self.exactValue(customNames, word) != nil { return true }
        guard !deletedNames.contains(word) else { return false }
        return Self.exactValue(baseNames, word) != nil
    }

    /// Khớp **trọn** chuỗi: khớp dài nhất từ đầu dài đúng bằng chuỗi (cách `checkWordInVietPhrase` / `existsInBaseDictionary`).
    private static func exactValue(_ dictionary: FrozenTrieDictionary?, _ word: String) -> String? {
        guard let dictionary, let match = dictionary.findLongestMatch(text: word, startIndex: 0),
              match.length == word.utf16.count else { return nil }
        return match.value
    }
}
