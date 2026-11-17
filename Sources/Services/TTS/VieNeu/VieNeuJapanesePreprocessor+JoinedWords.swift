import Foundation

/// Lối vào chữ của VieNeu (Nano và Turbo) — 1.3.975: từ điển phiên âm VieNeu khớp **từ có nối** (`S.H.I.E.L.D`,
/// `X-Men`, `v1.2`) theo luật token của thay thế từ TTS.
///
/// Bộ tiền xử lý vốn đã tra từ điển theo cả token có `-` / `.`, nhưng trên chữ **sau** `normalizeVietnameseText` — lúc
/// đó số La Mã / số thập phân đã làm vỡ token (`S.H.1.E.L.D`, `10-Men`). Ở đây từ nối được tra trên chữ gốc trước
/// (`TTSPhoneticJoinedWords`); phần chữ còn lại đi nguyên đường cũ.
extension VieNeuJapanesePreprocessor {
    /// Chữ gốc của một đoạn ⇒ chữ đưa cho bộ G2P: `normalizeVietnameseText` rồi `applyUsingStoredFlags`, với từ nối
    /// có trong từ điển phiên âm được thay trước. Từ điển tắt, rỗng, hoặc đoạn không có từ nối nào khớp ⇒ đúng kết
    /// quả cũ.
    static func synthesisText(for text: String) async -> String {
        guard UserDefaults.standard.bool(forKey: dictionaryEnabledKey) else {
            return await applyUsingStoredFlags(text: TextPreprocessor.normalizeVietnameseText(text))
        }
        let table = await VieNeuJapaneseDictionary.shared.all()
        var found: [TTSPhoneticJoinedWords.Piece]?
        if !table.isEmpty {
            found = TTSPhoneticJoinedWords.pieces(of: text) { word in
                table[VieNeuJapaneseDictionary.normalizedKey(word)]
            }
        }
        guard let pieces = found else {
            return await applyUsingStoredFlags(text: TextPreprocessor.normalizeVietnameseText(text))
        }

        var outputs: [String] = []
        outputs.reserveCapacity(pieces.count)
        for piece in pieces {
            if let reading = piece.reading {
                outputs.append(reading)
            } else {
                outputs.append(await applyUsingStoredFlags(text: TextPreprocessor.normalizeVietnameseText(piece.raw)))
            }
        }
        return TTSPhoneticJoinedWords.assemble(pieces, outputs: outputs)
    }
}
