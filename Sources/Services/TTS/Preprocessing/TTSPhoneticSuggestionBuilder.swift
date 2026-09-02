import Foundation

/// Dựng danh sách gợi ý phiên âm **bằng đúng đường mà NghiTTS dùng lúc đọc**.
///
/// Đây là bản rút gọn của `TextPreprocessor.transliterateToken`, giữ nguyên thứ tự quyết định:
/// 1. Gấp dấu phụ + hạ chữ thường (`folding(.diacriticInsensitive).lowercased()`) — pipeline tra từ
///    điển và cache bằng khoá đã gấp, nên gợi ý phải gấp giống hệt, nếu không hai bên tra khác nhau.
/// 2. Tra từ điển phiên âm.
/// 3. Cổng `ForeignScriptClassifier`: chỉ khi nó nói "tiếng Nhật" thì mới đi đường romaji. Bản cũ gọi
///    `transliterateRomaji` vô điều kiện nên với từ Anh cắt được kiểu romaji (`sonata`, `tomato`) nó
///    hiện một cách đọc Nhật mà pipeline sẽ không bao giờ chọn.
/// 4. Còn lại đi `EnglishPhonemeTransliterator` (espeak IPA), **không** phải `EnglishTransliterator`.
///
/// Khác pipeline đúng một chỗ có chủ ý: ở đây trả **cả hai** đường JP và EN để người dùng chọn tay,
/// và đánh dấu đường mà pipeline thật sự sẽ chọn (`isPipelineChoice`).
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

    /// `libraryHit` là kết quả tra từ điển phiên âm (caller lo vì nó là `actor`).
    public static func suggestions(
        for word: String,
        libraryHit: String?
    ) -> [TTSPhoneticSuggestion] {
        let key = normalizedKey(word)
        guard !key.isEmpty else { return [] }

        var result: [TTSPhoneticSuggestion] = []
        var seen = Set<String>()

        func append(_ raw: String, _ origin: TTSPhoneticSuggestion.Origin, isChoice: Bool) {
            let text = stripSyllableDashes(raw)
            guard !text.isEmpty, text.lowercased() != key else { return }
            guard seen.insert(text).inserted else { return }
            result.append(TTSPhoneticSuggestion(text: text, origin: origin, isPipelineChoice: isChoice))
        }

        // Từ điển thắng mọi đường khác trong pipeline, nên nếu có thì nó là lựa chọn thật.
        let hasLibrary = !(libraryHit ?? "").isEmpty
        if let libraryHit, !libraryHit.isEmpty {
            append(libraryHit, .library, isChoice: true)
        }

        let isJapanese = ForeignScriptClassifier.isJapaneseRomaji(key)

        let japanese = JapaneseTransliterator.transliterateRomaji(key)
        // `transliterateRomaji` trả **nguyên văn** khi không cắt được âm tiết; chuỗi đó không phải gợi ý.
        if japanese.lowercased() != key {
            append(japanese, .japanese, isChoice: !hasLibrary && isJapanese)
        }

        let english = EnglishPhonemeTransliterator.detailed(key)
        let origin: TTSPhoneticSuggestion.Origin = english.source == .espeak ? .englishIPA : .englishRule
        append(english.text, origin, isChoice: !hasLibrary && !isJapanese)

        return result
    }
}
