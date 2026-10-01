import Foundation

/// Tiền xử lý **riêng cho VieNeu-TTS**: gấp macron + từ điển tiếng Nhật + phiên âm romaji.
///
/// ## Ràng buộc cứng — KHÔNG có nhánh tiếng Anh
/// Không gọi `EnglishPhonemeTransliterator`, không gọi `EspeakPhonemizer`, và **không đọc
/// `PreprocessorRuntimeConfig`** (hai khoá `preprocessorTransliterationEnabled` /
/// `useEspeakIPAForEnglish` là của NghiTTS và sẽ kéo theo nhánh Anh/IPA). Token không phải tiếng Nhật và
/// không khớp từ điển thì **giữ nguyên** — đúng bằng hành vi trước khi có tính năng này, nên không hồi quy.
///
/// ## Vì sao đặt ở tầng service
/// `VieNeuTTSService.executeInternalSynthesis` gọi hàm này nên **cả Reader lẫn màn "Nghe thử"** đi cùng
/// một đường — đúng như lớp số/ngày (`normalizeVietnameseText`) đang làm.
enum VieNeuJapanesePreprocessor {

    /// Khoá `UserDefaults` **riêng của VieNeu** — cố ý **không** dùng `PreprocessorSettingKey` của NghiTTS.
    /// Cả hai mặc định **TẮT** (`bool(forKey:)` trả `false` khi khoá chưa có).
    static let dictionaryEnabledKey = "vieneuDictionaryEnabled"
    static let japaneseTransliterationEnabledKey = "vieneuJapaneseTransliterationEnabled"

    /// Gấp 5 nguyên âm macron về ASCII. **An toàn tuyệt đối, không cần cổng chặn**: `ā ī ū ē ō` không tồn
    /// tại trong bảng chữ tiếng Việt (a ă â e ê i o ô ơ u ư y + dấu thanh), nên phép gấp này **không thể**
    /// phá văn bản tiếng Việt. Đây cũng là lý do nó chạy **luôn**, không phụ thuộc cờ nào.
    private static let macronMap: [Character: Character] = [
        "ā": "a", "ī": "i", "ū": "u", "ē": "e", "ō": "o",
        "Ā": "A", "Ī": "I", "Ū": "U", "Ē": "E", "Ō": "O"
    ]

    static func foldMacrons(_ text: String) -> String {
        String(text.map { macronMap[$0] ?? $0 })
    }

    /// Đọc **cả hai** cờ từ `UserDefaults` rồi chạy. Tách ra để tầng service chỉ thêm **một dòng**.
    static func applyUsingStoredFlags(text: String) async -> String {
        let defaults = UserDefaults.standard
        return await apply(
            text: text,
            dictionaryEnabled: defaults.bool(forKey: dictionaryEnabledKey),
            japaneseTransliterationEnabled: defaults.bool(forKey: japaneseTransliterationEnabledKey)
        )
    }

    /// Thứ tự quyết định (giữ nguyên như đã chốt trong plan):
    /// 0. gấp macron — **luôn**;
    /// 1. cả hai cờ tắt ⇒ trả luôn (đường nhanh, không token hoá);
    /// 2. kana/katakana → romaji, chỉ khi cờ phiên âm bật;
    /// 3. từng token: **từ điển trước**, rồi mới tới đường romaji tự động.
    static func apply(
        text: String,
        dictionaryEnabled: Bool,
        japaneseTransliterationEnabled: Bool
    ) async -> String {
        let folded = foldMacrons(text)
        guard dictionaryEnabled || japaneseTransliterationEnabled else { return folded }

        // Lấy **cả bảng** một lần: tra từng token qua actor sẽ tốn một lượt nhảy actor cho mỗi token.
        let table = dictionaryEnabled ? await VieNeuJapaneseDictionary.shared.all() : [:]

        let pipelineInput = japaneseTransliterationEnabled
            ? JapaneseTransliterator.convertToRomaji(folded)
            : folded

        let source = pipelineInput as NSString
        let matches = PreprocessorRegex.token.matches(
            in: pipelineInput,
            options: [],
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else { return pipelineInput }

        var result = ""
        var lastOffset = 0
        for match in matches {
            if match.range.location > lastOffset {
                result += source.substring(with: NSRange(location: lastOffset, length: match.range.location - lastOffset))
            }
            let token = source.substring(with: match.range)
            result += replacement(
                for: token,
                table: table,
                japaneseTransliterationEnabled: japaneseTransliterationEnabled
            )
            lastOffset = match.range.location + match.range.length
        }
        if lastOffset < source.length {
            result += source.substring(with: NSRange(location: lastOffset, length: source.length - lastOffset))
        }
        return result
    }

    /// Một token: **từ điển thắng**, rồi mới tới đường tự động. Không khớp gì thì trả nguyên token.
    private static func replacement(
        for token: String,
        table: [String: String],
        japaneseTransliterationEnabled: Bool
    ) -> String {
        let key = VieNeuJapaneseDictionary.normalizedKey(token)
        if let hit = table[key] { return hit }
        guard japaneseTransliterationEnabled, token.count > 1 else { return token }
        guard ForeignScriptClassifier.isJapaneseRomaji(key) else { return token }
        let romaji = JapaneseTransliterator.transliterateRomaji(key)
        // `transliterateRomaji` trả **nguyên khoá** khi không cắt được thành âm tiết ⇒ không phải bản dịch.
        guard romaji.lowercased() != key else { return token }
        return romaji.replacingOccurrences(of: "-", with: " ")
    }
}
