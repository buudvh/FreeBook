import Foundation

/// Phiên âm tiếng Nhật cho các trình đọc **nhận chữ thô**: Siri, Google Cloud TTS, tiện ích TTS (1.3.973).
///
/// NghiTTS và VieNeu có bộ tiền xử lý riêng (`TextPreprocessor`, `VieNeuJapanesePreprocessor`) nên **không** đi qua đây.
/// Gọi ở tầng service của từng trình đọc (`SiriTTSService.speak`, `GoogleTTSService.synthesize` / `synthesizeBatch`,
/// `ExtTTSService.synthesizeData`) ⇒ đoạn đang đọc, nạp trước, đệm chương kế và "Nghe" đoạn bôi đen đi cùng một đường;
/// giọng dự phòng (NghiTTS / VieNeu) nhận chữ gốc và áp cài đặt của chính nó.
///
/// ## Đổi gì (cùng luật với nhánh tiếng Nhật của NghiTTS — `TextPreprocessor.transliterateToken`)
/// 1. Từ Latin là romaji (sau cổng `VietnameseTokenGate` để không đụng chữ Việt không dấu) ⇒ âm tiết Việt: "Sakura" →
///    "Xa cư ra". Token có gạch nối xét từng phần ("Naruto-kun"). "Là romaji" = `ForeignScriptClassifier` chấm đủ ngưỡng
///    **hoặc** (1.3.1037) đúng luật tên viết hoa của VieNeu (`VieNeuJapaneseNameReader.reads`: hoa đầu, ≥ 4 chữ, cắt hết
///    thành âm tiết romaji, không phải âm tiết Việt, không thuộc 507 từ tiếng Anh giống romaji). Trước đó chỉ có bộ chấm
///    điểm, mà ngưỡng 4 điểm cố ý nghiêng về tiếng Anh ⇒ "Konoha", "Naruto", "Sasuke" (1 điểm) không bao giờ được đổi —
///    anh Bửu bật công tắc cho vtts mà nghe vẫn tiếng Anh. Từ 1.3.1136 từ có nguyên âm dài ā ī ū ē ō ("Mangekyō",
///    "Ryūjin") mà cắt hết được thành âm romaji luôn là romaji (`ForeignScriptClassifier.hasHepburnLongVowel`).
/// 2. Dãy kana (hiragana / katakana) ⇒ romaji ⇒ âm tiết Việt. Chữ Hán giữ nguyên.
///
/// Không bao giờ trả rỗng cho đầu vào khác rỗng: từ không cắt được thành âm tiết thì giữ nguyên.
enum TTSJapaneseTextTransliterator {
    /// Theo công tắc "Phiên âm tiếng Nhật" của trình đọc `tool` (`TTSJapaneseTransliterationSettings`).
    static func apply(_ text: String, tool: String) -> String {
        guard TTSJapaneseTransliterationSettings.isEnabled(forTool: tool) else { return text }
        return transliterate(text)
    }

    /// Bản cho request gộp nhiều đoạn (Google): đọc công tắc **một lần**.
    static func apply(_ parts: [String], tool: String) -> [String] {
        guard TTSJapaneseTransliterationSettings.isEnabled(forTool: tool) else { return parts }
        return parts.map(transliterate)
    }

    /// Như `apply(_:tool:)` nhưng trả thêm công tắc và các cặp đã đổi ("Konoha→Kô nô ha") — cho dòng log của vtts.
    static func applyReportingChanges(_ text: String, tool: String) -> (text: String, isEnabled: Bool, changes: [String]) {
        guard TTSJapaneseTransliterationSettings.isEnabled(forTool: tool) else { return (text, false, []) }
        var changes: [String] = []
        let result = transliterate(text, changes: &changes)
        return (result, true, changes)
    }

    /// Phiên âm không xét công tắc. Romaji trước, kana sau: âm tiết Việt sinh từ kana không bị xét lại như từ Latin.
    static func transliterate(_ text: String) -> String {
        var ignored: [String] = []
        return transliterate(text, changes: &ignored)
    }

    private static func transliterate(_ text: String, changes: inout [String]) -> String {
        transliterateKanaRuns(in: transliterateRomajiTokens(in: text, changes: &changes), changes: &changes)
    }

    // MARK: - Romaji

    private static func transliterateRomajiTokens(in text: String, changes: inout [String]) -> String {
        let source = text as NSString
        let matches = PreprocessorRegex.token.matches(
            in: text, options: [], range: NSRange(location: 0, length: source.length)
        )
        var result = ""
        var lastOffset = 0
        for (index, match) in matches.enumerated() {
            let token = source.substring(with: match.range)
            guard isCandidate(token),
                  VietnameseTokenGate.shouldTransliterate(token, at: index, in: matches, source: source),
                  let spoken = spokenForm(of: token) else { continue }
            result += source.substring(with: NSRange(location: lastOffset, length: match.range.location - lastOffset))
            result += spoken
            changes.append("\(token)→\(spoken)")
            lastOffset = match.range.location + match.range.length
        }
        guard lastOffset > 0 else { return text }
        return result + source.substring(from: lastOffset)
    }

    /// Lọc rẻ trước khi vào cổng tiếng Việt + bộ chấm điểm: chỉ chữ Latin ASCII, nguyên âm macron và gạch nối, ≥ 2 chữ.
    /// Token có số, gạch dưới, dấu chấm ("S.H.I.E.L.D") hay dấu tiếng Việt bị loại ngay.
    private static func isCandidate(_ token: String) -> Bool {
        var letters = 0
        for scalar in token.unicodeScalars {
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A: letters += 1
            case 0x2D: continue
            default:
                guard macronVowels.contains(scalar) else { return false }
                letters += 1
            }
        }
        return letters > 1
    }

    private static let macronVowels = Set("āīūēōĀĪŪĒŌ".unicodeScalars)

    /// Token (có thể chứa gạch nối) ⇒ chữ để đọc; `nil` khi không phần nào là romaji.
    private static func spokenForm(of token: String) -> String? {
        let pieces = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        var changed = false
        let spoken = pieces.map { piece -> String in
            // Token ghép: phần trùng âm tiết Việt không dấu ("san" trong "Sasuke-san") giữ nguyên — như NghiTTS.
            if pieces.count > 1, VietnameseWordChecker.isVietnameseWord(piece) { return piece }
            // Bộ chấm điểm nhận `piece` còn nguyên ō (nguyên âm dài ⇒ romaji, 1.3.1136); luật tên của VieNeu chỉ nhận chữ
            // không dấu nên gấp ā ī ū ē ō trước, như đường VieNeu (`VieNeuJapanesePreprocessor.apply` gấp trước khi xét).
            guard piece.count > 1, JapaneseTransliterator.isJapaneseRomaji(piece)
                    || VieNeuJapaneseNameReader.reads(VieNeuJapanesePreprocessor.foldMacrons(piece)) else { return piece }
            let reading = JapaneseTransliterator.transliterateRomaji(piece)
            // `transliterateRomaji` trả **nguyên từ** khi không cắt được thành âm tiết ⇒ không phải bản phiên âm.
            guard reading.lowercased() != piece.lowercased() else { return piece }
            changed = true
            return matchingCase(reading.replacingOccurrences(of: "-", with: " "), like: piece)
        }
        return changed ? spoken.joined(separator: "-") : nil
    }

    /// Giữ chữ hoa đầu của tên riêng ("Sakura" → "Xa cư ra").
    private static func matchingCase(_ reading: String, like original: String) -> String {
        guard let first = original.first, first.isUppercase, let head = reading.first else { return reading }
        return head.uppercased() + reading.dropFirst()
    }

    // MARK: - Kana

    /// Hiragana `ぁ…ゖ`, katakana `ァ…ヺ` và dấu trường âm `ー`. Dấu chấm giữa `・` cố ý nằm ngoài: nó ngăn hai từ.
    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3041...0x3096, 0x30A1...0x30FA, 0x30FC: return true
        default: return false
        }
    }

    private static func transliterateKanaRuns(in text: String, changes: inout [String]) -> String {
        guard text.unicodeScalars.contains(where: isKana) else { return text }
        var result = ""
        var run = ""
        // Bản phiên âm vừa chèn đứng sát chữ / số phía sau ⇒ cần một dấu cách để không dính thành một từ.
        var needsSpaceBeforeWord = false
        for character in text {
            if character.unicodeScalars.allSatisfy(isKana) {
                run.append(character)
                continue
            }
            if !run.isEmpty {
                appendReading(of: run, to: &result, changes: &changes)
                run = ""
                needsSpaceBeforeWord = true
            }
            if needsSpaceBeforeWord, character.isLetter || character.isNumber { result.append(" ") }
            needsSpaceBeforeWord = false
            result.append(character)
        }
        if !run.isEmpty { appendReading(of: run, to: &result, changes: &changes) }
        return result
    }

    private static func appendReading(of kanaRun: String, to result: inout String, changes: inout [String]) {
        let romaji = JapaneseTransliterator.convertToRomaji(kanaRun)
        let reading = JapaneseTransliterator.transliterateRomaji(romaji).replacingOccurrences(of: "-", with: " ")
        if let last = result.last, last.isLetter || last.isNumber { result.append(" ") }
        result += reading.isEmpty ? kanaRun : reading
        if !reading.isEmpty { changes.append("\(kanaRun)→\(reading)") }
    }
}
