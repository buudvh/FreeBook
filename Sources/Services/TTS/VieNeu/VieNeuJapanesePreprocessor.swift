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

    /// Khoá `UserDefaults` **riêng của VieNeu** — cố ý **không** dùng `PreprocessorSettingKey` của NghiTTS. Mặc định
    /// **TẮT** (`bool(forKey:)` trả `false` khi khoá chưa có). Khoá phiên âm romaji (`vieneuJapaneseTransliterationEnabled`)
    /// không còn được đọc từ 1.3.899.
    static let dictionaryEnabledKey = "vieneuDictionaryEnabled"

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

    /// Đọc cờ từ điển từ `UserDefaults` rồi chạy. Tách ra để tầng service chỉ thêm **một dòng** (Nano và Turbo cùng gọi).
    ///
    /// **Phiên âm romaji tự động luôn tắt** từ 1.3.899 (công tắc "Tự động phiên âm tiếng Nhật" ở Cài đặt TTS đã bỏ): giá
    /// trị cũ ở khoá `vieneuJapaneseTransliterationEnabled` bị bỏ qua, không xoá. Từ điển phiên âm vẫn theo cờ của nó.
    static func applyUsingStoredFlags(text: String) async -> String {
        await apply(
            text: text,
            dictionaryEnabled: UserDefaults.standard.bool(forKey: dictionaryEnabledKey),
            japaneseTransliterationEnabled: false,
            nameSyllablesEnabled: VieNeuJapaneseNameReader.isEnabled
        )
    }

    /// Thứ tự quyết định (giữ nguyên như đã chốt trong plan):
    /// 0. gấp macron — **luôn**;
    /// 1. cả ba cờ tắt ⇒ trả luôn (đường nhanh, không token hoá);
    /// 2. kana/katakana → romaji, chỉ khi cờ phiên âm bật;
    /// 3. từng token: **từ điển trước**, rồi tên kiểu Nhật viết hoa (`VieNeuJapaneseNameReader`, 1.3.950 — cờ riêng,
    ///    mặc định bật), rồi mới tới đường romaji tự động.
    static func apply(
        text: String,
        dictionaryEnabled: Bool,
        japaneseTransliterationEnabled: Bool,
        nameSyllablesEnabled: Bool = false
    ) async -> String {
        let folded = foldMacrons(text)
        guard dictionaryEnabled || japaneseTransliterationEnabled || nameSyllablesEnabled else { return folded }

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
        var index = 0
        while index < matches.count {
            let match = matches[index]
            if match.range.location > lastOffset {
                result += source.substring(with: NSRange(location: lastOffset, length: match.range.location - lastOffset))
            }
            let token = source.substring(with: match.range)
            var consumedEnd = match.range.location + match.range.length
            // "Jun'ichi": bộ tách token cắt ở dấu nháy ⇒ ghép hai token liền nhau để tên được xét như một từ.
            if nameSyllablesEnabled, index + 1 < matches.count, consumedEnd < source.length,
               table.isEmpty || table[VieNeuJapaneseDictionary.normalizedKey(token)] == nil,
               source.character(at: consumedEnd) == 0x27, matches[index + 1].range.location == consumedEnd + 1,
               let joined = VieNeuJapaneseNameReader.replacement(
                   forHead: token, tail: source.substring(with: matches[index + 1].range)) {
                result += joined
                consumedEnd = matches[index + 1].range.location + matches[index + 1].range.length
                index += 1
            } else {
                result += replacement(
                    for: token,
                    table: table,
                    japaneseTransliterationEnabled: japaneseTransliterationEnabled,
                    nameSyllablesEnabled: nameSyllablesEnabled
                )
            }
            lastOffset = consumedEnd
            index += 1
        }
        if lastOffset < source.length {
            result += source.substring(with: NSRange(location: lastOffset, length: source.length - lastOffset))
        }
        return result
    }

    /// Một token: **từ điển thắng**, rồi tên kiểu Nhật, rồi mới tới đường tự động. Không khớp gì thì trả nguyên token.
    private static func replacement(
        for token: String,
        table: [String: String],
        japaneseTransliterationEnabled: Bool,
        nameSyllablesEnabled: Bool
    ) -> String {
        // Bảng rỗng (từ điển tắt) thì khỏi chuẩn hoá khoá: bước này chạy cho **mọi** token của mọi đoạn đọc.
        if !table.isEmpty, let hit = table[VieNeuJapaneseDictionary.normalizedKey(token)] { return hit }
        // Tên kiểu Nhật viết hoa ⇒ phiên âm theo âm tiết (1.3.950). Đứng **sau** từ điển để người dùng sửa tay được; token
        // có gạch nối thì từ điển được tra lại theo từng phần bên trong (1.3.960).
        if nameSyllablesEnabled, let name = VieNeuJapaneseNameReader.replacement(for: token, dictionary: table) { return name }
        guard japaneseTransliterationEnabled, token.count > 1 else { return token }
        let key = VieNeuJapaneseDictionary.normalizedKey(token)
        guard ForeignScriptClassifier.isJapaneseRomaji(key) else { return token }
        let romaji = JapaneseTransliterator.transliterateRomaji(key)
        // `transliterateRomaji` trả **nguyên khoá** khi không cắt được thành âm tiết ⇒ không phải bản dịch.
        guard romaji.lowercased() != key else { return token }
        return romaji.replacingOccurrences(of: "-", with: " ")
    }
}
