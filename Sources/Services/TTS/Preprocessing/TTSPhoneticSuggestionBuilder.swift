import Foundation

/// Dựng danh sách gợi ý phiên âm **bằng đúng đường mà NghiTTS dùng lúc đọc**.
///
/// Đây là bản rút gọn của `TextPreprocessor.transliterateToken`, giữ nguyên thứ tự quyết định:
/// 1. Gấp dấu phụ + hạ chữ thường (`folding(.diacriticInsensitive).lowercased()`) — pipeline tra từ
///    điển và cache bằng khoá đã gấp, nên gợi ý phải gấp giống hệt, nếu không hai bên tra khác nhau.
/// 2. Tra từ điển phiên âm — **cả hai** từ điển (NghiTTS + VieNeu), mỗi cái một chip riêng (1.3.462).
/// 3. Cổng `ForeignScriptClassifier`: chỉ khi nó nói "tiếng Nhật" thì mới đi đường romaji. Bản cũ gọi
///    `transliterateRomaji` vô điều kiện nên với từ Anh cắt được kiểu romaji (`sonata`, `tomato`) nó
///    hiện một cách đọc Nhật mà pipeline sẽ không bao giờ chọn.
/// 4. Còn lại đi `EnglishPhonemeTransliterator` (espeak IPA), **không** phải `EnglishTransliterator`.
///
/// Khác pipeline đúng một chỗ có chủ ý: ở đây trả **cả hai** đường JP và EN để người dùng chọn tay, và
/// đánh dấu nguồn đáng tin bằng `isPipelineChoice` (xem doc của thuộc tính đó).
public enum TTSPhoneticSuggestionBuilder {

    /// Khoá tra cứu giống pipeline: gấp dấu phụ rồi hạ chữ thường.
    public static func normalizedKey(_ word: String) -> String {
        word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .lowercased()
    }

    /// Bỏ dấu `-` mà các bộ phiên âm dùng để nối âm tiết (`xơ-trít` → `xơ trít`).
    ///
    /// Dấu đó chỉ là cách các transliterator đánh dấu ranh giới âm tiết; lưu vào từ điển thì nó thành
    /// một ký tự thật và đi tiếp vào espeak. Người dùng yêu cầu bỏ, nên gợi ý luôn ở dạng cách trắng.
    public static func stripSyllableDashes(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "-", with: " ")
        return spaced
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hai kết quả tra **từ điển phiên âm** (caller lo vì chúng là `actor`). Từ 1.3.462 phải truyền **cả
    /// hai**: chip `NGI` và `VIE` là hai nguồn độc lập, cùng một cách đọc vẫn hiện hai chip để người dùng
    /// biết mục nằm ở từ điển nào (chốt 2026-10-01).
    ///
    /// `includeEnglish = false` dùng cho **đích VieNeu**: engine đó **không** có nhánh tiếng Anh/IPA (ràng
    /// buộc cứng của tính năng từ điển tiếng Nhật), nên chip EN vừa vô nghĩa vừa tốn một lượt espeak.
    public static func suggestions(
        for word: String,
        nghiTTSHit: String?,
        vieNeuHit: String?,
        vttsHit: String? = nil,
        includeEnglish: Bool = true
    ) -> [TTSPhoneticSuggestion] {
        let key = normalizedKey(word)
        guard !key.isEmpty else { return [] }

        var result: [TTSPhoneticSuggestion] = []
        var seen = Set<String>()

        func append(_ raw: String, _ origin: TTSPhoneticSuggestion.Origin, isChoice: Bool) {
            let text = stripSyllableDashes(raw)
            guard !text.isEmpty, text.lowercased() != key else { return }
            // Khoá dedupe gồm **cả nguồn**, không chỉ `text`: hai từ điển độc lập có thể cùng cách đọc và
            // người dùng muốn thấy hai chip. Trước 1.3.462 dedupe chỉ theo `text` nên chip của từ điển kia
            // bị nuốt mất — đó chính là lỗi mà yêu cầu "trùng nghĩa vẫn để ra" nhắm vào.
            guard seen.insert(origin.rawValue + "|" + text).inserted else { return }
            result.append(TTSPhoneticSuggestion(text: text, origin: origin, isPipelineChoice: isChoice))
        }

        // Từ điển thắng mọi đường khác trong pipeline, nên mục nào có thì chip đó là lựa chọn thật — **cả
        // hai** đều `isChoice: true` (không phân biệt hơn kém giữa hai từ điển).
        if let nghiTTSHit, !nghiTTSHit.isEmpty {
            append(nghiTTSHit, .nghiTTSLibrary, isChoice: true)
        }
        if let vieNeuHit, !vieNeuHit.isEmpty {
            append(vieNeuHit, .vieNeuLibrary, isChoice: true)
        }
        if let vttsHit, !vttsHit.isEmpty {
            append(vttsHit, .vttsLibrary, isChoice: true)
        }
        let hasLibrary = !(nghiTTSHit ?? "").isEmpty || !(vieNeuHit ?? "").isEmpty || !(vttsHit ?? "").isEmpty

        // Khoá đã gấp dấu ⇒ báo riêng nguyên âm dài của từ gốc ("Mangekyō", 1.3.1136).
        let isJapanese = ForeignScriptClassifier.isJapaneseRomaji(
            key, hadLongVowel: ForeignScriptClassifier.hasHepburnLongVowel(word))

        let japanese = JapaneseTransliterator.transliterateRomaji(key)
        // `transliterateRomaji` trả **nguyên văn** khi không cắt được âm tiết; chuỗi đó không phải gợi ý.
        if japanese.lowercased() != key {
            append(japanese, .japanese, isChoice: !hasLibrary && isJapanese)
        }

        if includeEnglish {
            let english = EnglishPhonemeTransliterator.detailed(key)
            let origin: TTSPhoneticSuggestion.Origin = english.source == .espeak ? .englishIPA : .englishRule
            append(english.text, origin, isChoice: !hasLibrary && !isJapanese)
        }

        return result
    }

    /// Chip phiên âm **tự động** (JP / EN) cho ô "chuỗi thay thế" của luật thay thế TTS (1.3.974) — **không** tra từ
    /// điển phiên âm: luật thay thế chạy trước bộ phiên âm ở mọi trình đọc, nên chip chỉ cần đúng hai cách đọc máy
    /// tự sinh được.
    ///
    /// "Nếu có" (anh Bửu): không có chip nào khi từ có dấu tiếng Việt (cùng phép thử với `VietnameseTokenGate`),
    /// có số / dấu cách / dấu chấm / chữ Hán, hoặc dưới 2 chữ. Kana đổi sang romaji trước (như bước 0 của
    /// `TextPreprocessor.preprocess`) và chỉ có chip JP. Từ có gạch nối ("Sasuke-kun" — một token của
    /// `TTSReplacementTokenizer`) xét **từng phần**, ghép lại bằng dấu cách.
    ///
    /// Gọi ngoài main thread: đường EN vào `EspeakPhonemizer` (hàm C đồng bộ, khoá chung với NghiTTS).
    public static func transliterations(for word: String) -> [TTSPhoneticSuggestion] {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !VietnameseTokenGate.hasVietnameseDiacritic(trimmed) else { return [] }

        let romaji = JapaneseTransliterator.convertToRomaji(trimmed)
        let isKana = romaji != trimmed
        let key = normalizedKey(romaji)
        let pieces = key.split(separator: "-").map(String.init)
        guard pieces.joined().count > 1,
              pieces.allSatisfy({ piece in piece.allSatisfy { $0.isASCII && $0.isLetter } }) else { return [] }

        // Khoá đã gấp dấu ⇒ nguyên âm dài xét trên từ gốc, áp cho mọi phần ("Ryūjin-sama", 1.3.1136).
        let longVowel = ForeignScriptClassifier.hasHepburnLongVowel(trimmed)
        let japanesePieces = pieces.map {
            $0.count > 1 && ForeignScriptClassifier.isJapaneseRomaji($0, hadLongVowel: longVowel)
        }
        let isJapanese = isKana || japanesePieces.contains(true)
        var result: [TTSPhoneticSuggestion] = []

        func append(_ readings: [String], _ origin: TTSPhoneticSuggestion.Origin, isChoice: Bool) {
            let text = stripSyllableDashes(readings.joined(separator: " "))
            guard !text.isEmpty, text.lowercased() != pieces.joined(separator: " ") else { return }
            // Giữ chữ hoa đầu của tên riêng ("Sasuke" → "Xa xư kê"): chuỗi thay thế đi thẳng vào trình đọc nhận chữ
            // thô (Siri, Google, tiện ích), nơi chữ hoa còn có nghĩa.
            let cased = trimmed.first?.isUppercase == true ? text.prefix(1).uppercased() + text.dropFirst() : text
            result.append(TTSPhoneticSuggestion(text: cased, origin: origin, isPipelineChoice: isChoice))
        }

        // `transliterateRomaji` trả **nguyên văn** cả khi không cắt được âm tiết lẫn khi âm tiết đọc y như viết
        // ("kun", "ha"). Phần không đổi chỉ được nhận khi nó là romaji hoặc âm tiết Việt không dấu — không thì "Smith"
        // trong "Smith-san" cũng thành "phiên âm Nhật".
        let japanese = pieces.map { JapaneseTransliterator.transliterateRomaji($0) }
        let isSegmentable = pieces.indices.allSatisfy { index in
            japanese[index].lowercased() != pieces[index]
                || japanesePieces[index]
                || VietnameseWordChecker.isVietnameseWord(pieces[index])
        }
        if isSegmentable {
            append(japanese, .japanese, isChoice: isJapanese)
        }

        // Kana không có cách đọc tiếng Anh; bỏ luôn lượt espeak.
        if !isKana {
            let english = pieces.map { EnglishPhonemeTransliterator.detailed($0) }
            let usedEspeak = english.contains(where: { $0.source == .espeak })
            let origin: TTSPhoneticSuggestion.Origin = usedEspeak ? .englishIPA : .englishRule
            append(english.map(\.text), origin, isChoice: !isJapanese)
        }

        return result
    }
}
