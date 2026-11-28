import Foundation

/// Nghĩa đề xuất của một name (plan `Docs/Plans/2026-11-27-nghia-ten-tay-huyen.md` mục 1–3, `2026-11-27-phan-loai-name.md`
/// L7 / L10 / L11) — `Meanings.meaning` của bản tham chiếu `Docs/Plans/local-name-filter-lac/name_meaning.py` + `title_of`
/// của `lacpipe.py`, cho cả hàng bộ luật lẫn hàng phía LAC:
///
/// 1. Cả từ có trong từ điển với nghĩa kiểu tên (Name 3 lớp rồi VP 3 lớp, `LocalNameFilterProperNames.nameLike`) ⇒ nghĩa
///    đó (克莱恩 ⇒ Klein; bật "Ưu tiên tên Latin": 班森 ⇒ Benson). Nghĩa đầu viết thường (hàng luật (e)) không lấy.
/// 1b. Mọi loại trừ họ tộc (2026-11-28, plan "Tiền tố hậu tố riêng truyện" mục A1): bỏ tiền tố / hậu tố của danh sách (mọi
///    loại), phần lõi là tên Latin thật ⇒ "tiền tố + Latin + hậu tố" theo vị trí (古赫密斯语 ⇒ "cổ Hermes ngữ" —
///    `LocalNameFilterProperNames.latinAffixed`). Tên người vẫn báo danh xưng như đường khác.
/// 2. Không có ⇒ bóc như cũ, phần tên riêng dựng bằng `properAll` (từ điển ⇒ tiền tố ⇒ mô hình đoán ⇒ Hán-Việt):
///    - người + danh xưng ⇒ phần tên + nghĩa đầu của danh xưng giữ nguyên chữ (罗塞尔大帝 ⇒ "Russel đại đế"). Danh xưng =
///      hậu tố **Nhân danh dài nhất** của danh sách người dùng trong phần sau họ (`LocalNameFilterSetup.personTitle`: 陈长老
///      ⇒ "Trần trưởng lão", 天元圣女 ⇒ "Thiên Nguyên thánh nữ"); 1 chữ chỉ chữ thân tộc đã qua chốt của bộ luật
///      (`titles`). Không còn Pronouns. Người không danh xưng ⇒ `properAll` (họ theo Danh sách họ ở bước Hán-Việt);
///    - họ + 家 / 氏 / 族 ⇒ như cũ ("Tần gia");
///    - địa danh / tổ chức / thuật ngữ có đuôi ⇒ thử phủ trọn cả từ bằng mục từ điển mà mục cuối dài hơn đuôi
///      (贝克兰德 + 东区 — `coverAll`, chỉ name có phần tên Latin thật), không được thì phần riêng + nghĩa đuôi trước / sau.
///      Nghĩa đuôi lấy ở **danh sách người dùng** (cách A — mọi đuôi địa danh / tổ chức / thuật ngữ, kể cả 观 花 区): hậu tố
///      **dài nhất** của danh sách khớp cuối name, cho cả hàng LAC lẫn hàng bộ luật (2026-11-28: 瑶池仙阁 có hậu tố 仙阁 ⇒
///      "Dao Trì tiên các" — trước đó hàng bộ luật chỉ lấy đuôi đã dò 阁 nên 仙阁 của VP nuốt cả cụm); hàng bộ luật không có
///      hậu tố nào dài hơn ⇒ đúng đuôi đã dò, vắng trong danh sách ⇒ âm Hán-Việt viết thường đặt sau;
///    - không đuôi ⇒ `properAll`.
///    Tiền tố (老尼尔 ⇒ "lão Neil") áp ở từng mảnh trong `properAll`, theo nhóm: tiền tố loại `person` cho tên người, loại
///    khác cho name không phải người.
struct LocalNameFilterMeaningBuilder {
    typealias Word = LocalNameFilterWord

    struct Built {
        let meaning: String
        /// Danh xưng ở cuối (khoá hậu tố Nhân danh) nếu có.
        let title: Word?
        let isGuessed: Bool
    }

    let setup: LocalNameFilterSetup
    let dictionaries: LocalNameFilterDictionaries
    let properNames: LocalNameFilterProperNames

    // MARK: - Hàng bộ luật

    /// Nghĩa + danh xưng của một hàng bộ luật đã giữ (`extra` = số chữ họ với người / họ tộc, số chữ đuôi với địa danh /
    /// tông môn).
    func meaning(
        term: LocalNameFilterTermKey,
        kind: LocalNameFilter.Kind,
        extra: Int,
        titles: Set<LocalNameFilterTermKey>
    ) -> Built {
        let word = Word(term)
        let surnameLength = kind == .person || kind == .family ? extra : 0
        switch kind {
        case .person:
            return person(word, surnameLength: surnameLength, titles: titles)
        case .family:
            if let whole = properNames.nameLike(word) { return Built(meaning: whole, title: nil, isGuessed: false) }
            let meaning = properNames.reading(word.dropLast(1), surnameLength: surnameLength) + " "
                + dictionaries.phienAm(scalar: word.last).lowercased()
            return Built(meaning: meaning, title: nil, isGuessed: false)
        case .place, .sect:
            if let whole = properNames.nameLike(word) { return Built(meaning: whole, title: nil, isGuessed: false) }
            if let affixed = latinAffixed(word) { return affixed }
            guard extra > 0, extra < word.count else { return plain(word) }
            // Hậu tố dài hơn đuôi đã dò trong danh sách người dùng ⇒ ghép như hàng phía LAC (瑶池仙阁: 仙阁 thắng 阁).
            if let longest = setup.meaningSuffix(of: word), longest.length > extra {
                return suffixed(word, longest)
            }
            if let covered = properNames.coverAll(word, suffixLength: extra) {
                return Built(meaning: covered, title: nil, isGuessed: false)
            }
            let suffix = word.suffix(extra)
            let proper = properNames.properAll(word.dropLast(extra), surnameLength: 0, isPerson: false)
            if let configured = setup.meaningSuffix(suffix) {
                return Built(meaning: Self.compose(proper.text, configured), title: nil, isGuessed: proper.isGuessed)
            }
            // Đuôi đã dò mà người dùng đã xoá khỏi danh sách ⇒ âm Hán-Việt viết thường, đặt sau (như bản thử Python).
            let reading = suffix.scalars.map { dictionaries.phienAm(scalar: $0) }.joined(separator: " ")
            return Built(meaning: "\(proper.text) \(reading)", title: nil, isGuessed: proper.isGuessed)
        case .term:
            // Bộ luật không sinh ứng viên thuật ngữ.
            if let whole = properNames.nameLike(word) { return Built(meaning: whole, title: nil, isGuessed: false) }
            if let affixed = latinAffixed(word) { return affixed }
            return plain(word)
        }
    }

    // MARK: - Hàng phía LAC

    /// Nghĩa + danh xưng của một hàng phía LAC. `dictionaryTitle` (đợt 4, 2026-11-28): danh xưng lấy **từ từ điển** cho riêng
    /// name này — cụm LAC cắt cụt được nối một chữ mà cặp "chữ cuối + chữ nối" có trong từ điển (寒尸冥 + 将, 冥将 = "Minh
    /// Tướng" ⇒ "Hàn Thi Minh Tướng"); chỉ dùng khi danh sách hậu tố không có danh xưng nào khớp.
    func meaning(
        word: Word,
        kind: LocalNameFilter.Kind,
        titles: Set<LocalNameFilterTermKey>,
        dictionaryTitle: Word? = nil
    ) -> Built {
        if kind == .person {
            return person(word, surnameLength: dictionaries.surnameLength(of: word), titles: titles,
                          dictionaryTitle: dictionaryTitle)
        }
        if let whole = properNames.nameLike(word) { return Built(meaning: whole, title: nil, isGuessed: false) }
        if let affixed = latinAffixed(word) { return affixed }
        guard let suffix = setup.meaningSuffix(of: word) else { return plain(word) }
        return suffixed(word, suffix)
    }

    /// Tên kiểu Latin có tiền tố / hậu tố (`LocalNameFilterProperNames.latinAffixed`) — name không phải người; `nil` = không
    /// ra.
    private func latinAffixed(_ word: Word) -> Built? {
        properNames.latinAffixed(word).map { Built(meaning: $0.text, title: nil, isGuessed: $0.isGuessed) }
    }

    /// Name không phải người với hậu tố `suffix` của danh sách người dùng: phủ trọn cả từ (chỉ tên Latin) ⇒ nghĩa đó; không
    /// thì phần riêng + nghĩa hậu tố trước / sau.
    private func suffixed(_ word: Word, _ suffix: (length: Int, suffix: LocalNameFilter.Suffix)) -> Built {
        if let covered = properNames.coverAll(word, suffixLength: suffix.length) {
            return Built(meaning: covered, title: nil, isGuessed: false)
        }
        let proper = properNames.properAll(word.dropLast(suffix.length), surnameLength: 0, isPerson: false)
        return Built(meaning: Self.compose(proper.text, suffix.suffix), title: nil, isGuessed: proper.isGuessed)
    }

    // MARK: - Chung

    /// Tên người: cả từ trong từ điển ⇒ nghĩa đó (vẫn báo danh xưng); tên kiểu Latin có tiền tố / hậu tố ⇒ ghép theo vị trí
    /// (vẫn báo danh xưng); không thì phần tên + nghĩa danh xưng.
    private func person(
        _ word: Word,
        surnameLength: Int,
        titles: Set<LocalNameFilterTermKey>,
        dictionaryTitle: Word? = nil
    ) -> Built {
        var title = setup.personTitle(of: word, surnameLength: surnameLength, titles: titles)
        if title == nil, let key = dictionaryTitle, key.count < word.count,
           let raw = dictionaries.dictionaryValue(key.string), let meaning = LocalNameFilterRules.firstReading(raw) {
            title = (key: key, meaning: meaning)
        }
        if let whole = properNames.nameLike(word) { return Built(meaning: whole, title: title?.key, isGuessed: false) }
        if let affixed = properNames.latinAffixed(word) {
            return Built(meaning: affixed.text, title: title?.key, isGuessed: affixed.isGuessed)
        }
        if let title {
            let proper = properNames.properAll(word.dropLast(title.key.count), surnameLength: surnameLength, isPerson: true)
            return Built(meaning: proper.text + " " + title.meaning, title: title.key, isGuessed: proper.isGuessed)
        }
        let proper = properNames.properAll(word, surnameLength: surnameLength, isPerson: true)
        return Built(meaning: proper.text, title: nil, isGuessed: proper.isGuessed)
    }

    private func plain(_ word: Word) -> Built {
        let proper = properNames.properAll(word, surnameLength: 0, isPerson: false)
        return Built(meaning: proper.text, title: nil, isGuessed: proper.isGuessed)
    }

    /// Phần riêng + nghĩa đuôi giữ nguyên chữ, trước (`thành phố Giang Hải`) hoặc sau (`Lạc Hà trấn`).
    private static func compose(_ proper: String, _ suffix: LocalNameFilter.Suffix) -> String {
        suffix.position == .before ? "\(suffix.meaning) \(proper)" : "\(proper) \(suffix.meaning)"
    }
}
