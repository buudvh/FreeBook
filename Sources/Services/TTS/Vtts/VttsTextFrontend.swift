import Foundation

/// Chữ một đoạn ⇒ chữ đưa vào runtime vtts (1.3.1041): **từ điển phiên âm vtts** trước, **phiên âm tiếng Nhật** sau.
///
/// - Từ điển (`VttsPhoneticDictionary`, công tắc "Áp dụng từ điển phiên âm vtts"): tra từng token **từ** của
///   `TTSReplacementTokenizer` — cùng bộ tách với thay thế từ TTS và từ điển NghiTTS / VieNeu, nên từ nối (`Kamar-Taj`,
///   `S.H.I.E.L.D`) là một token và chỉ khớp nguyên cụm. Khoá giữ dấu, không phân biệt hoa thường.
/// - Cách đọc lấy từ từ điển đi **nguyên văn**: phần chữ còn lại mới qua `TTSJapaneseTextTransliterator` (công tắc "Phiên
///   âm tiếng Nhật" của vtts) ⇒ mục người dùng tự thêm luôn thắng, và cách đọc không bị phiên âm lần hai.
/// - Ghép các token lại ra đúng chữ gốc (bộ tách không bỏ ký tự nào) nên khoảng trắng / dấu câu quanh từ giữ nguyên.
enum VttsTextFrontend {
    struct Prepared {
        let text: String
        /// Số token đã thay bằng từ điển; `nil` khi công tắc từ điển tắt.
        let dictionaryHits: Int?
        let japaneseEnabled: Bool
        /// Cặp "từ→cách đọc" của bước phiên âm tiếng Nhật (cho log).
        let japaneseChanges: [String]
    }

    /// `dictionary == nil` ⇒ công tắc từ điển tắt.
    static func prepare(_ text: String, tool: String, dictionary: [String: String]?) -> Prepared {
        var segments: [(text: String, reading: String?)] = []
        var hits = 0
        if let dictionary, !dictionary.isEmpty {
            var pending = ""
            for token in TTSReplacementTokenizer.tokens(in: text) {
                guard token.kind == .word,
                      let reading = dictionary[VttsPhoneticDictionary.normalizedKey(token.text)],
                      !reading.isEmpty else {
                    pending += token.text
                    continue
                }
                if !pending.isEmpty {
                    segments.append((pending, nil))
                    pending = ""
                }
                segments.append((token.text, reading))
                hits += 1
            }
            if !pending.isEmpty { segments.append((pending, nil)) }
        } else {
            segments = [(text, nil)]
        }

        var output = ""
        var changes: [String] = []
        for segment in segments {
            if let reading = segment.reading {
                output += reading
                continue
            }
            let result = TTSJapaneseTextTransliterator.applyReportingChanges(segment.text, tool: tool)
            changes += result.changes
            output += result.text
        }
        return Prepared(
            text: output,
            dictionaryHits: dictionary == nil ? nil : hits,
            japaneseEnabled: TTSJapaneseTransliterationSettings.isEnabled(forTool: tool),
            japaneseChanges: changes
        )
    }
}
