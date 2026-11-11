import Foundation

/// Bảng phiên âm **đảo ngược**: âm Hán Việt ⇒ các chữ Hán có âm đó (gợi ý chữ Hán ở màn Tìm — `ChineseQuerySuggester`).
///
/// Dựng từ `phienAm` của từ điển chung (chữ ⇒ âm; một chữ có thể nhiều âm, ngăn bằng `/` `,` `;` `|` hoặc khoảng
/// trắng). Chỉ lấy khoá **một** đơn vị UTF-16 trong vùng chữ Hán: cây từ điển tra theo từng đơn vị UTF-16 nên chữ
/// ngoài BMP (cặp surrogate) sẽ lệch phép đi cây, và khoá nhiều chữ không phải âm của một chữ.
///
/// Hai bảng: `exact` theo âm **có dấu**, `folded` theo âm **bỏ dấu** (gõ không dấu). Khoá âm được chuẩn hoá
/// (`Syllable`) để các cách gõ khác nhau vẫn khớp: chữ thường, NFC; **vị trí** dấu thanh không tính (`hoà` = `hòa`,
/// `thuỷ` = `thủy`); `y` đứng một mình sau phụ âm coi như `i` (`lý` = `lí`, `quý` = `quí`); `đ` bỏ dấu là `d`.
///
/// Bản dựng được nhớ theo `TranslationDictionaryState.revision()` — từ điển đổi thì lần gọi sau dựng lại.
struct HanVietReverseIndex: Sendable {
    /// Một âm tiết đã chuẩn hoá. `exact` = phần chữ giữ dấu mũ/móc/trăng + số thanh (0 = ngang); `folded` = chỉ
    /// chữ `a`–`z`.
    struct Syllable: Sendable, Equatable {
        let exact: String
        let folded: String
        /// Có dấu thanh, dấu mũ/móc/trăng hoặc `đ` ⇒ âm tiết này khớp đúng dấu; không có ⇒ khớp bỏ dấu.
        let hasDiacritics: Bool
    }

    let exact: [String: Set<UInt16>]
    let folded: [String: Set<UInt16>]

    /// Chữ có âm `syllable`. Khớp đúng dấu khi `matchingDiacritics`; nếu âm có dấu không ra chữ nào (gõ sai dấu)
    /// thì lùi về khớp bỏ dấu cho riêng âm tiết đó.
    func characters(for syllable: Syllable, matchingDiacritics: Bool) -> Set<UInt16> {
        if matchingDiacritics, let hits = exact[syllable.exact], !hits.isEmpty { return hits }
        return folded[syllable.folded] ?? []
    }

    // MARK: - Bản nhớ theo revision

    private static let cacheLock = NSLock()
    private static var cached: (revision: UInt64, index: HanVietReverseIndex)?

    /// Bản dựng cho đúng `revision` của từ điển; dựng (trong khoá, chỉ lần đầu sau mỗi lần từ điển đổi) khi chưa có.
    static func index(phienAm: [String: String], revision: UInt64) -> HanVietReverseIndex {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached, cached.revision == revision { return cached.index }
        let built = build(from: phienAm)
        cached = (revision, built)
        return built
    }

    private static func build(from phienAm: [String: String]) -> HanVietReverseIndex {
        var exact: [String: Set<UInt16>] = [:]
        var folded: [String: Set<UInt16>] = [:]
        // Chỉ vài nghìn âm khác nhau cho vài chục nghìn chữ ⇒ chuẩn hoá mỗi âm một lần.
        var syllableByReading: [Substring: Syllable?] = [:]
        for (character, reading) in phienAm {
            guard let unit = singleHanUnit(character) else { continue }
            for token in reading.split(whereSeparator: isReadingSeparator) {
                let parsed: Syllable?
                if let known = syllableByReading[token] {
                    parsed = known
                } else {
                    parsed = Syllable(String(token))
                    syllableByReading[token] = parsed
                }
                guard let syllable = parsed else { continue }
                exact[syllable.exact, default: []].insert(unit)
                folded[syllable.folded, default: []].insert(unit)
            }
        }
        return HanVietReverseIndex(exact: exact, folded: folded)
    }

    /// Đơn vị UTF-16 của khoá khi khoá đúng **một** chữ Hán trong BMP (khối chính, mở rộng A, chữ tương thích).
    private static func singleHanUnit(_ key: String) -> UInt16? {
        let units = key.utf16
        guard units.count == 1, let unit = units.first else { return nil }
        switch unit {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: return unit
        default: return nil
        }
    }

    private static func isReadingSeparator(_ character: Character) -> Bool {
        character.isWhitespace || character == "/" || character == "," || character == ";" || character == "|"
    }
}

extension HanVietReverseIndex.Syllable {
    /// Dấu thanh (dạng tổ hợp sau NFD) ⇒ số thanh. U+0340/U+0341 cũ được NFD đưa về U+0300/U+0301.
    private static let toneByMark: [UInt32: Int] = [
        0x0301: 1, // sắc
        0x0300: 2, // huyền
        0x0309: 3, // hỏi
        0x0303: 4, // ngã
        0x0323: 5  // nặng
    ]

    /// Dấu đổi **chữ** (không phải thanh): mũ `â ê ô`, trăng `ă`, móc `ơ ư`.
    private static let letterMarks: Set<UInt32> = [0x0302, 0x0306, 0x031B]

    /// `nil` khi chuỗi không phải một âm tiết chữ Latin tiếng Việt (có số, chữ Hán, dấu câu, hai dấu thanh…).
    init?(_ raw: String) {
        var tone = 0
        var hasDiacritics = false
        var base = String.UnicodeScalarView()
        var folded = String.UnicodeScalarView()
        for scalar in raw.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            if let mark = Self.toneByMark[scalar.value] {
                guard tone == 0, !folded.isEmpty else { return nil }
                tone = mark
                hasDiacritics = true
            } else if Self.letterMarks.contains(scalar.value) {
                guard !folded.isEmpty else { return nil }
                base.append(scalar)
                hasDiacritics = true
            } else if scalar.value == 0x0111 { // đ — không tách được bằng NFD
                base.append(scalar)
                folded.append("d")
                hasDiacritics = true
            } else if (0x61...0x7A).contains(scalar.value) {
                base.append(scalar)
                folded.append(scalar)
            } else {
                return nil
            }
        }
        guard !folded.isEmpty else { return nil }
        var exactText = String(base).precomposedStringWithCanonicalMapping
        var foldedText = String(folded)
        if Self.endsWithLoneY(foldedText) {
            exactText = String(exactText.dropLast()) + "i"
            foldedText = String(foldedText.dropLast()) + "i"
        }
        self.init(exact: exactText + String(tone), folded: foldedText, hasDiacritics: hasDiacritics)
    }

    /// `y` là nguyên âm duy nhất, đứng sau phụ âm đầu (kể cả `qu`): `ly`, `ky`, `my`, `quy`, `y`.
    private static func endsWithLoneY(_ folded: String) -> Bool {
        guard folded.hasSuffix("y") else { return false }
        var onset = folded.dropLast()
        if onset.hasPrefix("qu") { onset = onset.dropFirst(2) }
        return !onset.contains { "aeiouy".contains($0) }
    }
}
