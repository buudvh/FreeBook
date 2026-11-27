import Foundation

/// Nghĩa đề xuất của một name (plan `Docs/Plans/2026-11-27-nghia-ten-tay-huyen.md` mục 1–3) — `Meanings.meaning` của bản
/// tham chiếu `Docs/Plans/local-name-filter-lac/name_meaning.py`, cho cả hàng bộ luật lẫn hàng phía LAC:
///
/// 1. Cả từ có trong từ điển với nghĩa kiểu tên (Name 3 lớp rồi VP 3 lớp, `LocalNameFilterProperNames.nameLike`) ⇒ nghĩa
///    đó (克莱恩 ⇒ Klein; bật "Ưu tiên tên Latin": 班森 ⇒ Benson). Nghĩa đầu viết thường (hàng luật (e)) không lấy.
/// 2. Không có ⇒ bóc như cũ, phần tên riêng dựng bằng `properAll` (từ điển ⇒ mô hình đoán ⇒ Hán-Việt):
///    - người + danh xưng (Pronouns, như cũ) ⇒ phần tên + nghĩa đầu của danh xưng giữ nguyên chữ (罗塞尔大帝 ⇒ "Russel
///      đại đế"); người không danh xưng ⇒ `properAll` (họ theo Danh sách họ ở bước Hán-Việt);
///    - họ + 家 / 氏 / 族 ⇒ như cũ ("Tần gia");
///    - địa danh / tổ chức / thuật ngữ có đuôi ⇒ thử phủ trọn cả từ bằng mục từ điển mà mục cuối dài hơn đuôi
///      (贝克兰德 + 东区 — `coverAll`), không được thì phần riêng + nghĩa đuôi trước / sau. Nghĩa đuôi lấy ở **danh sách người dùng** (cách A — mọi đuôi, kể cả 观 花 区):
///      hàng LAC lấy đuôi dài nhất của danh sách; hàng bộ luật lấy đúng đuôi đã dò, vắng trong danh sách ⇒ âm Hán-Việt
///      viết thường đặt sau;
///    - không đuôi ⇒ `properAll`.
struct LocalNameFilterMeaningBuilder {
    typealias Word = LocalNameFilterWord

    struct Built {
        let meaning: String
        /// Danh xưng ở cuối (khoá Pronouns) nếu có.
        let title: LocalNameFilterTermKey?
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
        var title: LocalNameFilterTermKey?
        if kind == .person, !titles.isEmpty, let tail = setup.pronounTail(of: term, surnameLength: surnameLength),
           titles.contains(tail), setup.pronouns[tail] != nil {
            title = tail
        }
        if let whole = properNames.nameLike(word) { return Built(meaning: whole, title: title, isGuessed: false) }
        switch kind {
        case .person:
            return person(word, surnameLength: surnameLength, title: title)
        case .family:
            let meaning = properNames.reading(word.dropLast(1), surnameLength: surnameLength) + " "
                + dictionaries.phienAm(scalar: word.last).lowercased()
            return Built(meaning: meaning, title: nil, isGuessed: false)
        case .place, .sect:
            guard extra > 0, extra < word.count else { return plain(word) }
            if let covered = properNames.coverAll(word, suffixLength: extra) {
                return Built(meaning: covered, title: nil, isGuessed: false)
            }
            let suffix = word.suffix(extra)
            let proper = properNames.properAll(word.dropLast(extra), surnameLength: 0)
            if let configured = setup.meaningSuffix(suffix) {
                return Built(meaning: Self.compose(proper.text, configured), title: nil, isGuessed: proper.isGuessed)
            }
            // Đuôi đã dò mà người dùng đã xoá khỏi danh sách ⇒ âm Hán-Việt viết thường, đặt sau (như bản thử Python).
            let reading = suffix.scalars.map { dictionaries.phienAm(scalar: $0) }.joined(separator: " ")
            return Built(meaning: "\(proper.text) \(reading)", title: nil, isGuessed: proper.isGuessed)
        case .term:
            // Bộ luật không sinh ứng viên thuật ngữ.
            return plain(word)
        }
    }

    // MARK: - Hàng phía LAC

    /// `surname_len(w)` của `lacpipe.py`: họ kép khi từ ≥ 3 chữ, rồi họ đơn khi từ ≥ 2 chữ, không có ⇒ 0.
    func surnameLength(of word: Word) -> Int {
        if word.count >= 3, let key = word.slice(0, 2).termKey, dictionaries.surnames[key] != nil { return 2 }
        if word.count >= 2, let key = word.slice(0, 1).termKey, dictionaries.surnames[key] != nil { return 1 }
        return 0
    }

    /// Nghĩa + danh xưng của một hàng phía LAC.
    func meaning(word: Word, kind: LocalNameFilter.Kind, titles: Set<LocalNameFilterTermKey>) -> Built {
        if kind == .person {
            let head = surnameLength(of: word)
            var title: LocalNameFilterTermKey?
            if !titles.isEmpty, let tail = setup.pronounTail(of: word, surnameLength: head), titles.contains(tail),
               setup.pronouns[tail] != nil {
                title = tail
            }
            if let whole = properNames.nameLike(word) { return Built(meaning: whole, title: title, isGuessed: false) }
            return person(word, surnameLength: head, title: title)
        }
        if let whole = properNames.nameLike(word) { return Built(meaning: whole, title: nil, isGuessed: false) }
        guard let suffix = setup.meaningSuffix(of: word) else { return plain(word) }
        if let covered = properNames.coverAll(word, suffixLength: suffix.length) {
            return Built(meaning: covered, title: nil, isGuessed: false)
        }
        let proper = properNames.properAll(word.dropLast(suffix.length), surnameLength: 0)
        return Built(meaning: Self.compose(proper.text, suffix.suffix), title: nil, isGuessed: proper.isGuessed)
    }

    // MARK: - Chung

    private func person(_ word: Word, surnameLength: Int, title: LocalNameFilterTermKey?) -> Built {
        if let title, let pronounMeaning = setup.pronouns[title] {
            let proper = properNames.properAll(word.dropLast(title.count), surnameLength: surnameLength)
            return Built(meaning: proper.text + " " + pronounMeaning, title: title, isGuessed: proper.isGuessed)
        }
        let proper = properNames.properAll(word, surnameLength: surnameLength)
        return Built(meaning: proper.text, title: nil, isGuessed: proper.isGuessed)
    }

    private func plain(_ word: Word) -> Built {
        let proper = properNames.properAll(word, surnameLength: 0)
        return Built(meaning: proper.text, title: nil, isGuessed: proper.isGuessed)
    }

    /// Phần riêng + nghĩa đuôi giữ nguyên chữ, trước (`thành phố Giang Hải`) hoặc sau (`Lạc Hà trấn`).
    private static func compose(_ proper: String, _ suffix: LocalNameFilter.Suffix) -> String {
        suffix.position == .before ? "\(suffix.meaning) \(proper)" : "\(proper) \(suffix.meaning)"
    }
}
