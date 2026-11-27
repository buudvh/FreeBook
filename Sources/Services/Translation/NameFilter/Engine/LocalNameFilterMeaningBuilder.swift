import Foundation

/// Nghĩa đề xuất của một name — `Dicts.reading` + phần dựng `r["meaning"]` trong `decide` của bản thử Python.
///
/// - Tên người: âm Hán-Việt viết hoa từng âm (họ lấy âm trong Danh sách họ, không có thì phiên âm từng chữ).
/// - Địa danh / tông môn: phần tên riêng viết hoa + nghĩa đuôi theo danh sách, đặt sau (mặc định) hoặc trước
///   (落霞镇 → "Lạc Hà trấn"; 市 = "thành phố · trước" ⇒ 江海市 → "thành phố Giang Hải").
/// - Họ + 家 / 氏 / 族 → "Tần gia" (âm của chữ cuối viết thường, đặt sau).
/// - Tên + danh xưng: phần tên viết hoa + nghĩa đầu của danh xưng trong từ điển Đại từ, giữ nguyên chữ
///   (江镖头 → "Giang tiêu đầu").
/// - Hàng phía LAC (`meaning(word:…)`, `meaning()` của `lacpipe.py`): người như trên (họ dò theo Danh sách họ: họ kép
///   khi từ ≥ 3 chữ, rồi họ đơn); có đuôi (địa danh / tổ chức / thuật ngữ) ⇒ phần riêng viết hoa + nghĩa đuôi trước /
///   sau (五气丹 → "Ngũ Khí đan"); không đuôi ⇒ âm từng chữ viết hoa như tên người.
struct LocalNameFilterMeaningBuilder {
    let setup: LocalNameFilterSetup
    let dictionaries: LocalNameFilterDictionaries

    /// `d.reading(term, surname_len)`.
    func reading(_ term: LocalNameFilterTermKey?, surnameLength: Int) -> String {
        guard let term else { return "" }
        var parts: [String] = []
        var rest = term.units[...]
        if surnameLength > 0 {
            let surnameUnits = term.units.prefix(surnameLength)
            if let reading = dictionaries.surnames[LocalNameFilterTermKey(units: Array(surnameUnits))], !reading.isEmpty {
                parts.append(reading)
            } else {
                parts.append(surnameUnits.map { dictionaries.phienAm($0) }.joined(separator: " "))
            }
            rest = term.units.dropFirst(surnameLength)
        }
        parts.append(contentsOf: rest.map { dictionaries.phienAm($0) })
        return LocalNameFilterRules.capitalizeWords(parts.joined(separator: " "))
    }

    /// Nghĩa + danh xưng (nếu có) của một hàng đã giữ.
    func meaning(
        term: LocalNameFilterTermKey,
        kind: LocalNameFilter.Kind,
        extra: Int,
        titles: Set<LocalNameFilterTermKey>
    ) -> (meaning: String, title: LocalNameFilterTermKey?) {
        let surnameLength = kind == .person || kind == .family ? extra : 0
        var meaning = reading(term, surnameLength: surnameLength)
        var title: LocalNameFilterTermKey?
        switch kind {
        case .place, .sect:
            if let suffix = term.suffix(extra) {
                let proper = reading(term.dropLast(suffix.count), surnameLength: 0)
                if let configured = setup.suffixMeaning(suffix, kind: kind) {
                    meaning = configured.position == .before
                        ? "\(configured.meaning) \(proper)"
                        : "\(proper) \(configured.meaning)"
                } else {
                    // Python: đuôi không khai nghĩa ⇒ phiên âm, đặt sau (Configuration luôn có nghĩa — chỉ để chắc).
                    meaning = "\(proper) \(suffix.units.map { dictionaries.phienAm($0) }.joined(separator: " "))"
                }
            }
        case .family:
            meaning = reading(term.dropLast(1), surnameLength: surnameLength) + " "
                + dictionaries.phienAm(term.last).lowercased()
        case .person:
            if !titles.isEmpty, let tail = setup.pronounTail(of: term, surnameLength: surnameLength), titles.contains(tail),
               let pronounMeaning = setup.pronouns[tail] {
                meaning = reading(term.dropLast(tail.count), surnameLength: surnameLength) + " " + pronounMeaning
                title = tail
            }
        case .term:
            // Bộ luật không sinh ứng viên thuật ngữ — hàng thuật ngữ đi `meaning(word:…)`.
            break
        }
        return (meaning, title)
    }

    // MARK: - Phía LAC

    /// `rd.reading(w, sl)` cho từ dài tuỳ ý (chữ ngoài bảng phiên âm giữ nguyên, như `phienam.get(c, c)`).
    func reading(word: LocalNameFilterWord, surnameLength: Int) -> String {
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

    /// `surname_len(w)` của `lacpipe.py`: họ kép khi từ ≥ 3 chữ, rồi họ đơn khi từ ≥ 2 chữ, không có ⇒ 0.
    func surnameLength(of word: LocalNameFilterWord) -> Int {
        if word.count >= 3, let key = word.slice(0, 2).termKey, dictionaries.surnames[key] != nil { return 2 }
        if word.count >= 2, let key = word.slice(0, 1).termKey, dictionaries.surnames[key] != nil { return 1 }
        return 0
    }

    /// Nghĩa + danh xưng của một hàng phía LAC.
    func meaning(
        word: LocalNameFilterWord,
        kind: LocalNameFilter.Kind,
        suffix: (length: Int, suffix: LocalNameFilter.Suffix)?,
        titles: Set<LocalNameFilterTermKey>
    ) -> (meaning: String, title: LocalNameFilterTermKey?) {
        if kind == .person {
            let head = self.surnameLength(of: word)
            if !titles.isEmpty, let tail = setup.pronounTail(of: word, surnameLength: head), titles.contains(tail),
               let pronounMeaning = setup.pronouns[tail] {
                return (reading(word: word.dropLast(tail.count), surnameLength: head) + " " + pronounMeaning, tail)
            }
            return (reading(word: word, surnameLength: head), nil)
        }
        guard let suffix else { return (reading(word: word, surnameLength: 0), nil) }
        let proper = reading(word: word.dropLast(suffix.length), surnameLength: 0)
        let meaning = suffix.suffix.position == .before
            ? "\(suffix.suffix.meaning) \(proper)"
            : "\(proper) \(suffix.suffix.meaning)"
        return (meaning, nil)
    }
}
