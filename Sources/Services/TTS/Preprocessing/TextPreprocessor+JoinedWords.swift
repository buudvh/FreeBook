import Foundation

/// Từ điển phiên âm NghiTTS khớp **từ có nối** (`Kamar-Taj`, `S.H.I.E.L.D`, `e-mail`) theo luật token của thay thế từ
/// TTS — 1.3.975. Lý do phải tra trên chữ gốc và cách cắt: `TTSPhoneticJoinedWords`.
extension TextPreprocessor {
    /// Chữ gốc có từ nối nằm trong từ điển ⇒ kết quả tiền xử lý của cả đoạn; không có ⇒ `nil`, `preprocess` đi
    /// nguyên đường cũ.
    ///
    /// Phần chữ quanh từ nối đi lại qua `preprocess` (không còn từ nối nào khớp nên không lặp vô hạn: mỗi lượt cắt
    /// bỏ ít nhất một từ). Cách đọc lấy từ từ điển đi nguyên văn như bước tra từ điển sẵn có.
    func preprocessAroundJoinedWords(_ text: String, config: PreprocessorRuntimeConfig) -> String? {
        guard config.dictionaryReplacementEnabled, !wordMap.isEmpty else { return nil }
        let table = wordMap
        let found = TTSPhoneticJoinedWords.pieces(of: text) { word in
            // `updateWord` lưu khoá hạ chữ thường; bước tra từng token thì tra bằng khoá đã gấp dấu phụ ⇒ thử cả hai.
            let lowered = word.lowercased()
            return table[lowered] ?? table[lowered.folding(options: .diacriticInsensitive, locale: nil)]
        }
        guard let pieces = found else { return nil }

        var outputs: [String] = []
        outputs.reserveCapacity(pieces.count)
        var hits = 0
        for piece in pieces {
            if let reading = piece.reading {
                outputs.append(reading)
                hits += 1
            } else {
                outputs.append(preprocess(piece.raw))
            }
        }
        AppLogger.shared.log("🚀 [Preprocess] Từ nối có trong từ điển phiên âm: \(hits) từ, tra trên chữ gốc.")
        return TTSPhoneticJoinedWords.assemble(pieces, outputs: outputs)
    }
}
