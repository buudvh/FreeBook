import Foundation

/// Đọc **tên riêng kiểu Nhật** theo âm tiết cho VieNeu (Nano và Turbo) — 1.3.950.
///
/// ## Vì sao
/// Từ điển của `SeaG2P` đọc mọi chữ Latin không dấu theo luật chính tả **tiếng Anh**, nên tên Nhật bị mất chữ ngay từ
/// bước phiên âm: "Sasuke" → `sˈæsuːk` (mất "ke"), "Takemichi" → `tˈeɪk mˈɪtʃaɪ`, "Akame" → `ˈækeɪm`. Ở đây tên được cắt
/// thành âm tiết romaji rồi sinh thẳng phiên âm (`VieNeuRomajiSyllabifier`), đi nguyên văn qua `SeaG2P`.
///
/// ## Từ nào được đổi (đủ cả bốn điều kiện, xét **sau** khi `VieNeuJapanesePreprocessor.foldMacrons` đã gấp ā ī ū ē ō)
/// 1. viết hoa chữ đầu, phần còn lại chữ thường, toàn chữ Latin không dấu (riêng `û`, `î` được gấp tại đây), ≥ 4 chữ;
/// 2. cắt được **hết** thành âm tiết romaji;
/// 3. không phải âm tiết Việt không dấu ("Tuan", "Hoan" — `VietnameseWordChecker`);
/// 4. không thuộc `VieNeuRomajiEnglishLookalikes` (game, time, kate, tomato…).
///
/// Token có gạch nối được xét từng phần ("Sasuke-kun"); phần sau gạch nối là hậu tố xưng hô thì đọc theo âm tiết luôn.
/// Dấu nháy sau "n" ("Jun'ichi") do bên gọi ghép hai token rồi hỏi `replacement(forHead:tail:)`.
///
/// ## Giới hạn đã biết
/// Tên 3 chữ ("Rem", "Rin") và chữ có mũ ô / â / ê ("Tôkyô" — trùng chữ Việt) không tự đổi; từ tiếng Anh hiếm, viết
/// hoa, có dạng romaji mà nằm ngoài danh sách loại trừ sẽ bị đọc theo âm tiết. Từ điển phiên âm của người dùng luôn
/// được tra **trước** (`VieNeuJapanesePreprocessor`) nên sửa tay được từng từ; công tắc "Phiên âm tiếng Nhật" của VieNeu
/// (`isEnabled`) tắt cả tính năng.
enum VieNeuJapaneseNameReader {
    /// Khoá **cũ** của công tắc "Đọc tên Nhật theo âm tiết" (1.3.950–972). Từ 1.3.973 công tắc là "Phiên âm tiếng Nhật"
    /// chung mọi trình đọc, lưu riêng từng trình đọc (`TTSJapaneseTransliterationSettings`); khoá này chỉ còn là giá trị
    /// khởi đầu cho VieNeu (chưa có ⇒ **bật**), không ai ghi nữa.
    static let enabledKey = "vieneuJapaneseNameSyllablesEnabled"

    static var isEnabled: Bool {
        TTSJapaneseTransliterationSettings.isEnabled(forTool: TTSJapaneseTransliterationSettings.vieNeuTool)
    }

    private static let honorifics: Set<String> = [
        "kun", "san", "chan", "sama", "senpai", "sempai", "sensei", "dono", "tan", "chin"
    ]
    private static let minimumLetters = 4

    /// Một token của `PreprocessorRegex.token` (có thể chứa gạch nối) ⇒ chuỗi thay thế, hoặc `nil` nếu không có phần nào
    /// là tên kiểu Nhật.
    ///
    /// `dictionary` = từ điển phiên âm của người dùng (khoá `VieNeuJapaneseDictionary.normalizedKey`), tra **từng phần**
    /// trước khi đọc theo âm tiết (1.3.960): bộ tiền xử lý tra từ điển theo cả token "Sasuke-kun", nên mục "Sasuke" chỉ áp
    /// được ở đây. Phần đầu có trong từ điển vẫn tính là tên ⇒ hậu tố xưng hô sau nó vẫn đọc theo âm tiết.
    static func replacement(for token: String, dictionary: [String: String] = [:]) -> String? {
        guard let first = token.unicodeScalars.first, isUppercaseLatin(first), !token.contains(".") else { return nil }
        let pieces = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard !pieces.contains(where: \.isEmpty) else { return nil }
        func entry(_ piece: String) -> String? {
            dictionary.isEmpty ? nil : dictionary[VieNeuJapaneseDictionary.normalizedKey(piece)]
        }
        let head: String
        if let hit = entry(pieces[0]) {
            head = hit
        } else if let name = namePhonemes(pieces[0]) {
            head = marked(name)
        } else {
            return nil
        }
        var output = [head]
        for piece in pieces.dropFirst() {
            if let hit = entry(piece) {
                output.append(hit)
            } else if let name = namePhonemes(piece) {
                output.append(marked(name))
            } else if let suffix = honorificPhonemes(piece) {
                output.append(marked(suffix))
            } else {
                output.append(piece)
            }
        }
        return output.joined(separator: " ")
    }

    /// Hai token nối bằng dấu nháy sau "n" ("Jun" + "ichi", "Shin" + "ya"): dấu nháy báo "n" thuộc âm tiết trước.
    static func replacement(forHead head: String, tail: String) -> String? {
        guard head.last == "n", let first = tail.first, "aiueoy".contains(first), isLowercaseLatin(tail) else { return nil }
        guard let key = nameKey(head, minimumLetters: 2), key.count + tail.count >= minimumLetters else { return nil }
        guard !VieNeuRomajiEnglishLookalikes.words.contains(key + tail),
              let syllables = VieNeuRomajiSyllabifier.syllables(of: key + "'" + tail) else { return nil }
        return marked(VieNeuRomajiSyllabifier.phonemes(of: syllables))
    }

    /// Từ đứng một mình có được đọc theo âm tiết không — cho `VieNeuForeignTextClassifier` (tên đã đổi thì không còn
    /// là "tiếng nước ngoài" cần chuyển sang Turbo).
    static func reads(_ word: String) -> Bool {
        if let quote = word.firstIndex(of: "'") {
            return replacement(forHead: String(word[..<quote]), tail: String(word[word.index(after: quote)...])) != nil
        }
        return namePhonemes(word) != nil
    }

    /// Mẩu đứng sau gạch nối của token mà phần đầu là `head` có được đổi không ("sensei" trong "Kakashi-sensei") — cho
    /// `VieNeuForeignTextClassifier`, vốn tách token ở gạch nối nên không tự thấy điều này. `dictionaryKeys` = khoá từ điển
    /// phiên âm đang bật: cùng luật với `replacement(for:dictionary:)` (phần có trong từ điển tính như tên).
    static func readsSuffix(_ piece: String, afterHead head: String, dictionaryKeys: Set<String> = []) -> Bool {
        func known(_ word: String) -> Bool {
            !dictionaryKeys.isEmpty && dictionaryKeys.contains(VieNeuJapaneseDictionary.normalizedKey(word))
        }
        guard known(head) || namePhonemes(head) != nil else { return false }
        return known(piece) || namePhonemes(piece) != nil || honorificPhonemes(piece) != nil
    }

    // MARK: - Cổng nhận dạng

    /// Hậu tố xưng hô ⇒ phiên âm. Cắt với tối thiểu **một** âm tiết: "kun", "san", "chan", "tan", "chin" chỉ có một
    /// (trước 1.3.956 dùng mặc định hai âm tiết nên năm hậu tố này không bao giờ được đổi, "kun" bị đọc theo tiếng Anh).
    private static func honorificPhonemes(_ piece: String) -> [String]? {
        let key = piece.lowercased()
        guard honorifics.contains(key),
              let syllables = VieNeuRomajiSyllabifier.syllables(of: key, minimumSyllables: 1) else { return nil }
        return VieNeuRomajiSyllabifier.phonemes(of: syllables)
    }

    private static func namePhonemes(_ piece: String) -> [String]? {
        guard let key = nameKey(piece, minimumLetters: minimumLetters) else { return nil }
        guard !VietnameseWordChecker.isVietnameseWord(key), !VieNeuRomajiEnglishLookalikes.words.contains(key),
              let syllables = VieNeuRomajiSyllabifier.syllables(of: key) else { return nil }
        return VieNeuRomajiSyllabifier.phonemes(of: syllables)
    }

    /// Chữ hoa đầu + chữ thường phía sau, toàn Latin không dấu (sau khi gấp `û`, `î`) ⇒ khoá chữ thường; còn lại `nil`.
    private static func nameKey(_ piece: String, minimumLetters: Int) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in piece.unicodeScalars {
            switch scalar {
            case "\u{FB}": scalars.append("u")  // û
            case "\u{EE}": scalars.append("i")  // î
            case "\u{DB}": scalars.append("U")  // Û
            case "\u{CE}": scalars.append("I")  // Î
            default: scalars.append(scalar)
            }
        }
        guard scalars.count >= minimumLetters, let first = scalars.first, isUppercaseLatin(first) else { return nil }
        guard scalars.dropFirst().allSatisfy({ $0.value >= 0x61 && $0.value <= 0x7A }) else { return nil }
        return String(scalars).lowercased()
    }

    private static func isUppercaseLatin(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 0x41 && scalar.value <= 0x5A) || scalar.value == 0xDB || scalar.value == 0xCE  // Û, Î
    }

    private static func isLowercaseLatin(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { $0.value >= 0x61 && $0.value <= 0x7A }
    }

    // MARK: - Đánh dấu

    /// Bọc **từng âm tiết** bằng cặp ký hiệu để `SeaG2P` chuyển nguyên văn; các âm tiết cách nhau một dấu cách thường
    /// nên bộ cắt chunk vẫn cắt được ở ranh giới âm tiết như với mọi từ khác.
    private static func marked(_ parts: [String]) -> String {
        parts
            .map { String(SeaG2P.rawPhonemeOpen) + $0 + String(SeaG2P.rawPhonemeClose) }
            .joined(separator: " ")
    }
}
