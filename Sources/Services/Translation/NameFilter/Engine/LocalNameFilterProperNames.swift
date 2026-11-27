import Foundation

/// Nghĩa **phần tên riêng** của nghĩa đề xuất theo từ điển (plan `Docs/Plans/2026-11-27-nghia-ten-tay-huyen.md` mục 2–3)
/// — `Meanings` của bản tham chiếu `Docs/Plans/local-name-filter-lac/name_meaning.py`:
///
/// - `nameLike`: nghĩa thô trong từ điển (Name 3 lớp rồi VP 3 lớp, `LocalNameFilterDictionaries.dictionaryValue`) ⇒ chọn
///   bằng `pick` ⇒ chỉ nhận khi viết hoa chữ đầu (nghĩa kiểu tên).
/// - `pick`: nghĩa đầu (tách `/` `|` `¦`, bỏ mục rỗng); "Ưu tiên tên Latin" (có mô hình) + từ trông như phiên âm ⇒ nghĩa
///   chữ Latin đầu tiên nếu có (班森 Ban Sâm/Benson ⇒ Benson; 金边 Kim Biên/Phnom Penh giữ Kim Biên).
/// - `properAll`: tách theo `·` `.` `•` (bỏ dấu ngăn, nối bằng dấu cách); mỗi mảnh: cả mảnh `coverEntry` ⇒ nghĩa đó; phủ
///   **trọn** bằng mục ≥ 2 chữ `coverEntry` (từ trái, thử dài → ngắn) ⇒ ghép (贝克兰德 + 东区); còn sót chữ lẻ ⇒ không ghép
///   lai ("Mạc Bear"): Latin + mảnh trông như phiên âm ⇒ mô hình đoán (`isGuessed`); còn lại ⇒ âm Hán-Việt như cũ (họ theo
///   Danh sách họ ở mảnh đầu của tên người).
/// - `coverEntry` (siết 2026-11-27, anh Bửu duyệt — bỏ ca lạ 黑礁岛 ⇒ "Black Lagoon đảo", 炎珠草 ⇒ "Viên viêm châu thảo"):
///   **mọi** mục từ điển dùng làm một phần của nghĩa (cả mảnh — phần riêng trước đuôi / danh xưng, mảnh tách theo `·` — và
///   mục ghép) phải `nameLike` **và** nghĩa là kiểu tên Hán-Việt (không phải chữ Latin, viết hoa chữ đầu **mọi** từ: "Đông
///   Khu") hoặc chữ Latin mà khoá có **≥ 1 chữ** thuộc tập chữ phiên âm (`hasTranslitChar` — không dùng ngưỡng "≥ nửa"
///   vì tập thiếu nhiều chữ thông dụng như 戴 里 图 铎). Chỉ đường "cả từ" (`nameLike` của cả name, ở
///   `LocalNameFilterMeaningBuilder`) không siết.
/// - Tập chữ phiên âm (`LocalNameFilterTranslitChars`, đóng trong app — cách C) dùng ở **mọi** chế độ: tắt Latin vẫn nhận
///   罗塞尔 ⇒ Russel, 戴里克.伯格 ⇒ Derrick Berg; công tắc chỉ thêm chọn nghĩa Latin (`pick`) + đoán.
/// - `coverAll`: phép phủ trọn cả từ dùng trước khi bóc đuôi (xem hàm).
/// - **Tiền tố** (plan 2026-11-27-phan-loai-name L7 / L10, `prefixed`): mảnh không có cả mảnh trong từ điển mà mở đầu bằng
///   một tiền tố của danh sách "Tiền tố" **cùng nhóm** (tiền tố loại `person` ⇄ tên người, loại khác ⇄ name không phải
///   người), dài nhất trước, phần sau ≥ 2 chữ: nghĩa cả mảnh dạng "nghĩa tiền tố + Tên" (老尼尔=lão Neil) ⇒ nhận; không thì
///   phần sau ra tên **Latin** (cả phần / phủ trọn bằng `coverEntry`, hoặc mô hình đoán khi bật Latin và **mọi** chữ là chữ
///   phiên âm) ⇒ "nghĩa tiền tố + tên" theo vị trí (老科勒 ⇒ "lão Kolle"); không ra Latin ⇒ đi tiếp như cũ (小鱼 ⇒ "Tiểu
///   Ngư", 老张 ⇒ "Lão Trương").
///
/// Một đối tượng cho cả lượt lọc (`LocalNameFilterEngine` giữ) — nhớ kết quả qua mọi lần chụp. **Không khoá**: chỉ dùng
/// trên task của lượt lọc, như `LocalNameFilterDictionaries`.
final class LocalNameFilterProperNames {
    typealias Word = LocalNameFilterWord

    struct Proper {
        let text: String
        /// Có mảnh do mô hình đoán.
        let isGuessed: Bool
    }

    private struct ProperKey: Hashable {
        let piece: Word
        let surnameLength: Int
        let isPerson: Bool
    }

    /// Mục từ điển dài nhất thử khi phủ một mảnh (`MAX_PIECE` của Python).
    private static let maxPieceLength = 12
    /// Dấu ngăn tên: `·` (U+00B7), `.`, `•` (U+2022).
    private static let separators: Set<UInt32> = [0x00B7, 0x2E, 0x2022]
    private static let alternativeSeparators: Set<Character> = ["/", "|", "¦"]
    /// Chữ riêng tiếng Việt (ă â đ ê ô ơ ư + chữ có dấu thanh) — đúng bộ `VIET` của Python / `export_translit.py`.
    private static let vietnameseScalars: Set<UInt32> = {
        var set = Set("ăâđêôơưĂÂĐÊÔƠƯàáãèéìíòóõùúýÀÁÃÈÉÌÍÒÓÕÙÚÝĩũĨŨ".unicodeScalars.map(\.value))
        for value in UInt32(0x1EA0)..<UInt32(0x1EFA) { set.insert(value) }
        return set
    }()

    private let dictionaries: LocalNameFilterDictionaries
    /// `nil` = tắt "Ưu tiên tên Latin" hoặc bật mà không có mô hình (tải lỗi) — khi đó như tắt.
    private let latinModel: LocalNameFilterLatinModel?
    /// Tập chữ phiên âm (code point) — luôn có, không theo công tắc.
    private let translitChars: Set<UInt32>
    /// Danh sách "Tiền tố" theo khoá (`Configuration.prefixes`).
    private let prefixes: [Word: LocalNameFilter.Suffix]
    private let prefixMaxLength: Int
    /// Chuỗi rỗng = không có nghĩa kiểu tên.
    private var nameLikeMemo: [Word: String] = [:]
    /// Như `nameLikeMemo` cho `coverEntry`.
    private var coverEntryMemo: [Word: String] = [:]
    private var properMemo: [ProperKey: Proper] = [:]

    /// `translitChars` mặc định là tập đóng trong app; truyền vào chỉ để thử. `prefixes` rỗng ⇒ không ghép tiền tố.
    init(
        dictionaries: LocalNameFilterDictionaries,
        latinModel: LocalNameFilterLatinModel?,
        prefixes: [LocalNameFilter.Suffix] = [],
        translitChars: Set<UInt32> = LocalNameFilterTranslitChars.set
    ) {
        self.dictionaries = dictionaries
        self.latinModel = latinModel
        self.translitChars = translitChars
        var table: [Word: LocalNameFilter.Suffix] = [:]
        for prefix in prefixes {
            let word = Word(prefix.key)
            guard (1...LocalNameFilterSuffixListParser.maxKeyLength).contains(word.count), table[word] == nil else { continue }
            table[word] = prefix
        }
        self.prefixes = table
        prefixMaxLength = table.keys.map(\.count).max() ?? 0
    }

    var prefersLatin: Bool { latinModel != nil }

    // MARK: - Từ điển

    /// ≥ một nửa số chữ thuộc tập chữ phiên âm (mọi chế độ).
    func looksTransliterated(_ word: Word) -> Bool {
        guard !translitChars.isEmpty, !word.isEmpty else { return false }
        let hits = word.scalars.reduce(0) { $0 + (translitChars.contains($1) ? 1 : 0) }
        return 2 * hits >= word.count
    }

    /// Có ≥ 1 chữ thuộc tập chữ phiên âm — ngưỡng của luật "mảnh chữ Latin" ở `coverEntry` (session chính chọn,
    /// 2026-11-27): tập 268 chữ thiếu nhiều chữ phiên âm thông dụng (戴 里 图 铎…) nên ngưỡng "≥ nửa" làm hỏng 戴里克 ⇒
    /// Derrick, 所罗门 ⇒ Solomon, 查拉图 ⇒ Zaratul; "≥ 1 chữ" giữ được chúng mà vẫn chặn 黑礁 ⇒ "Black Lagoon" (không chữ
    /// nào). Mất 图铎 ⇒ Tudor khi là mảnh của name dài hơn (cả từ 图铎 vẫn ra Tudor).
    func hasTranslitChar(_ word: Word) -> Bool {
        word.scalars.contains { translitChars.contains($0) }
    }

    /// Nghĩa dùng cho tên trong nghĩa thô `raw` của khoá `key`.
    func pick(_ raw: String, key: Word) -> String {
        let alternatives = raw.split(whereSeparator: { Self.alternativeSeparators.contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = alternatives.first else { return "" }
        if latinModel != nil, looksTransliterated(key), let latin = alternatives.first(where: Self.isLatinName) {
            return latin
        }
        return first
    }

    /// Nghĩa kiểu tên của cả khoá (viết hoa chữ đầu), `nil` = không có.
    func nameLike(_ word: Word) -> String? {
        if let cached = nameLikeMemo[word] { return cached.isEmpty ? nil : cached }
        var result = ""
        if let raw = dictionaries.dictionaryValue(word.string) {
            let picked = pick(raw, key: word)
            if picked.first?.isUppercase == true { result = picked }
        }
        nameLikeMemo[word] = result
        return result.isEmpty ? nil : result
    }

    /// `cover_entry`: nghĩa của một mục dùng làm **phần** của nghĩa (cả mảnh, mục ghép) — `nameLike` và (a) không phải chữ
    /// Latin, mọi từ viết hoa chữ đầu; hoặc (b) chữ Latin mà khoá có ≥ 1 chữ phiên âm. Không đạt ⇒ `nil` ("Black Lagoon"
    /// của 黑礁, "Viên viêm châu" của 炎珠).
    func coverEntry(_ word: Word) -> String? {
        if let cached = coverEntryMemo[word] { return cached.isEmpty ? nil : cached }
        var result = ""
        if let meaning = nameLike(word) {
            if Self.isLatinName(meaning) {
                if hasTranslitChar(word) { result = meaning }
            } else if meaning.split(whereSeparator: \.isWhitespace).allSatisfy({ $0.first?.isUppercase == true }) {
                result = meaning
            }
        }
        coverEntryMemo[word] = result
        return result.isEmpty ? nil : result
    }

    /// `is_latin_name`: viết hoa chữ đầu, không có chữ riêng tiếng Việt, có ít nhất một chữ cái.
    static func isLatinName(_ text: String) -> Bool {
        guard text.first?.isUppercase == true, text.contains(where: \.isLetter) else { return false }
        return !text.unicodeScalars.contains { vietnameseScalars.contains($0.value) }
    }

    // MARK: - Tên riêng

    /// Phần tên riêng (có thể có dấu ngăn). `surnameLength` chỉ áp cho mảnh đầu (bước Hán-Việt); `isPerson` = phần tên
    /// của tên người (chọn nhóm tiền tố).
    func properAll(_ word: Word, surnameLength: Int, isPerson: Bool) -> Proper {
        var texts: [String] = []
        var isGuessed = false
        let pieces = word.scalars.split(omittingEmptySubsequences: false) { Self.separators.contains($0) }
        for (index, piece) in pieces.enumerated() where !piece.isEmpty {
            let proper = self.proper(
                Word(scalars: Array(piece)), surnameLength: index == 0 ? surnameLength : 0, isPerson: isPerson
            )
            texts.append(proper.text)
            isGuessed = isGuessed || proper.isGuessed
        }
        return Proper(text: texts.joined(separator: " "), isGuessed: isGuessed)
    }

    /// Một mảnh không có dấu ngăn.
    func proper(_ piece: Word, surnameLength: Int, isPerson: Bool) -> Proper {
        let key = ProperKey(piece: piece, surnameLength: surnameLength, isPerson: isPerson)
        if let cached = properMemo[key] { return cached }
        let result = uncachedProper(piece, surnameLength: surnameLength, isPerson: isPerson)
        properMemo[key] = result
        return result
    }

    private func uncachedProper(_ piece: Word, surnameLength: Int, isPerson: Bool) -> Proper {
        if let whole = coverEntry(piece) { return Proper(text: whole, isGuessed: false) }
        if let prefixed = prefixed(piece, isPerson: isPerson) { return prefixed }
        if let covered = cover(piece) { return Proper(text: covered, isGuessed: false) }
        if let latinModel, looksTransliterated(piece), let guess = latinModel.predict(piece.scalars) {
            return Proper(text: guess, isGuessed: true)
        }
        return Proper(text: reading(piece, surnameLength: surnameLength), isGuessed: false)
    }

    // MARK: - Tiền tố

    /// `prefixed` của `name_meaning.py` (xem doc của type); `nil` = không ghép tiền tố.
    private func prefixed(_ piece: Word, isPerson: Bool) -> Proper? {
        guard prefixMaxLength > 0 else { return nil }
        let longest = min(prefixMaxLength, piece.count - 2)
        guard longest >= 1 else { return nil }
        var raw: String?
        for length in stride(from: longest, through: 1, by: -1) {
            guard let prefix = prefixes[piece.slice(0, length)], (prefix.kind == .person) == isPerson else { continue }
            if raw == nil { raw = dictionaries.dictionaryValue(piece.string).map { pick($0, key: piece) } ?? "" }
            let whole = raw ?? ""
            // Nghĩa cả mảnh dạng "nghĩa tiền tố + Tên" (老尼尔=lão Neil) / "Tên + nghĩa tiền tố".
            switch prefix.position {
            case .before:
                if whole.hasPrefix(prefix.meaning + " "), whole.dropFirst(prefix.meaning.count + 1).first?.isUppercase == true {
                    return Proper(text: whole, isGuessed: false)
                }
            case .after:
                if whole.hasSuffix(" " + prefix.meaning), whole.first?.isUppercase == true {
                    return Proper(text: whole, isGuessed: false)
                }
            }
            if let latin = latinName(of: piece.slice(length, piece.count)) {
                let text = prefix.position == .before ? "\(prefix.meaning) \(latin.text)" : "\(latin.text) \(prefix.meaning)"
                return Proper(text: text, isGuessed: latin.isGuessed)
            }
        }
        return nil
    }

    /// `latin_of`: tên Latin của phần sau tiền tố — cả phần / phủ trọn bằng `coverEntry` mà nghĩa là chữ Latin; không có
    /// trong từ điển ⇒ mô hình đoán khi bật Latin và **mọi** chữ là chữ phiên âm. Không ra Latin ⇒ `nil`.
    private func latinName(of rest: Word) -> Proper? {
        if let found = coverEntry(rest) ?? cover(rest) {
            return Self.isLatinName(found) ? Proper(text: found, isGuessed: false) : nil
        }
        if let latinModel, !translitChars.isEmpty, rest.scalars.allSatisfy({ translitChars.contains($0) }),
           let guess = latinModel.predict(rest.scalars) {
            return Proper(text: guess, isGuessed: true)
        }
        return nil
    }

    // MARK: - Phủ cả từ

    /// `cover_all`: name không phải người có đuôi `suffixLength` chữ — mọi mảnh (tách theo dấu ngăn) có cả mảnh trong từ
    /// điển hoặc phủ trọn được, **và** mục cuối dài hơn đuôi (ranh giới đuôi rơi giữa mục) ⇒ ghép; không ⇒ `nil`. Gọi
    /// **trước** khi bóc đuôi: 贝克兰德 + 东区 ⇒ "Backlund Đông khu" (区 là đuôi ghép nghĩa, bóc trước thì mất 东区); mục cuối
    /// trùng đúng đuôi (三元 + 圣体) ⇒ `nil`, để nghĩa đuôi theo danh sách người dùng ("Tam Nguyên thánh thể").
    func coverAll(_ word: Word, suffixLength: Int) -> String? {
        var texts: [String] = []
        var lastLength = 0
        for piece in word.scalars.split(whereSeparator: { Self.separators.contains($0) }) {
            let piece = Word(scalars: Array(piece))
            if let whole = coverEntry(piece) {
                texts.append(whole)
                lastLength = piece.count
                continue
            }
            guard let parts = coverParts(piece), let last = parts.last else { return nil }
            texts.append(contentsOf: parts.map { $0.text })
            lastLength = last.length
        }
        guard !texts.isEmpty, lastLength > suffixLength else { return nil }
        return texts.joined(separator: " ")
    }

    /// Phủ trọn mảnh bằng các mục ≥ 2 chữ `coverEntry`, khớp dài nhất từ trái; còn chữ lẻ ⇒ `nil`.
    private func cover(_ piece: Word) -> String? {
        coverParts(piece).map { parts in parts.map { $0.text }.joined(separator: " ") }
    }

    /// Các mục phủ trọn mảnh (độ dài + nghĩa), theo thứ tự; còn chữ lẻ ⇒ `nil`.
    private func coverParts(_ piece: Word) -> [(length: Int, text: String)]? {
        var parts: [(length: Int, text: String)] = []
        var start = 0
        let count = piece.count
        while start < count {
            var hit: (end: Int, text: String)?
            for end in stride(from: min(count, start + Self.maxPieceLength), through: start + 2, by: -1) {
                if let text = coverEntry(piece.slice(start, end)) {
                    hit = (end, text)
                    break
                }
            }
            guard let hit else { return nil }
            parts.append((hit.end - start, hit.text))
            start = hit.end
        }
        return parts.isEmpty ? nil : parts
    }

    /// `d.reading(w, sl)`: họ lấy âm trong Danh sách họ (không có thì phiên âm từng chữ), phần còn lại phiên âm từng chữ;
    /// viết hoa chữ đầu mỗi âm. Chữ ngoài bảng phiên âm giữ nguyên.
    func reading(_ word: Word, surnameLength: Int) -> String {
        var parts: [String] = []
        var rest = word.scalars[...]
        if surnameLength > 0 {
            let surname = word.slice(0, surnameLength)
            if let key = surname.termKey, let reading = dictionaries.surnames[key], !reading.isEmpty {
                parts.append(reading)
            } else {
                parts.append(surname.scalars.map { dictionaries.phienAm(scalar: $0) }.joined(separator: " "))
            }
            rest = word.scalars.dropFirst(surnameLength)
        }
        parts.append(contentsOf: rest.map { dictionaries.phienAm(scalar: $0) })
        return LocalNameFilterRules.capitalizeWords(parts.joined(separator: " "))
    }
}
