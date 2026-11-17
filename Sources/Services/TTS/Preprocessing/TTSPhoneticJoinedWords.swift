import Foundation

/// Từ **có nối** trong từ điển phiên âm NghiTTS / VieNeu (1.3.975): `-` hoặc `.` kẹp giữa hai chữ / số, không dấu
/// cách — `Kamar-Taj`, `S.H.I.E.L.D`, `X-Men`, `v1.2`.
///
/// Ranh giới từ lấy từ `TTSReplacementTokenizer` — **cùng một hàm** với thay thế từ TTS, nên mục từ điển và luật thay
/// thế hiểu "một từ" giống nhau: cả token khớp mới áp (mục `Kamar-Taj` thắng mục `Kamar`), `Kamar-`, `Taj,` không
/// phải một từ.
///
/// ## Vì sao phải tra trên chữ **gốc**, trước đường tiền xử lý
/// Đường tiền xử lý làm vỡ từ nối trước khi tới bước tra từ điển:
/// - số La Mã: `S.H.I.E.L.D` → `S.H.1.E.L.D`, `X-Men` → `10-Men`; số thập phân: `v1.2` → `v một phẩy hai`
///   (`processVietnameseText`, NghiTTS lẫn VieNeu);
/// - NghiTTS còn đổi mọi `-` không nằm giữa hai chữ số thành dấu cách (`cleanEmojisAndSymbols`), và bước tra cụm chỉ
///   ghép tối đa 4 mẩu.
///
/// Vì vậy chữ gốc được cắt quanh từ nối có trong từ điển: phần còn lại đi **nguyên đường cũ**, cách đọc lấy từ từ điển
/// đi **nguyên văn** (không qua đọc số, không bị tra từ điển lần hai). Đoạn không có từ nối nào khớp ⇒ `pieces` trả
/// `nil`, nơi gọi không đổi gì — mục không có `-` / `.` giữ đúng hành vi cũ.
enum TTSPhoneticJoinedWords {
    /// Một mẩu của chữ gốc. `reading == nil` ⇒ chữ thường, đi tiếp đường tiền xử lý; có `reading` ⇒ từ nối đã tra được.
    struct Piece: Equatable, Sendable {
        let raw: String
        let reading: String?
    }

    /// Từ (đã là một token của `TTSReplacementTokenizer`) có `-` / `.` bên trong.
    static func isJoined(_ word: String) -> Bool {
        word.contains(where: TTSReplacementTokenizer.isJoiner)
    }

    /// Cắt `text` quanh các từ nối mà `reading` trả cách đọc khác rỗng. `nil` khi không có từ nào như vậy.
    ///
    /// Ghép `raw` của mọi mẩu lại ra đúng `text` — không chữ nào rơi.
    static func pieces(of text: String, reading: (String) -> String?) -> [Piece]? {
        guard isJoined(text) else { return nil }
        var result: [Piece] = []
        var pending = ""
        var found = false
        for token in TTSReplacementTokenizer.tokens(in: text) {
            guard token.kind == .word, isJoined(token.text),
                  let value = reading(token.text)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                pending += token.text
                continue
            }
            if !pending.isEmpty {
                result.append(Piece(raw: pending, reading: nil))
                pending = ""
            }
            result.append(Piece(raw: token.text, reading: value))
            found = true
        }
        guard found else { return nil }
        if !pending.isEmpty {
            result.append(Piece(raw: pending, reading: nil))
        }
        return result
    }

    /// Ghép lại sau khi nơi gọi đã xử lý từng mẩu: `outputs[i]` là kết quả của `pieces[i]` (mẩu có `reading` thì truyền
    /// chính `reading`).
    ///
    /// Đường tiền xử lý cắt khoảng trắng hai đầu từng mẩu, nên khoảng trắng ở chỗ nối được trả lại theo chữ gốc (một
    /// dấu cách). Mẩu chữ bị dọn hết (chỉ khoảng trắng, ký hiệu bị bỏ) vẫn là chỗ ngắt — hai cách đọc không bao giờ
    /// dính liền nhau.
    static func assemble(_ pieces: [Piece], outputs: [String]) -> String {
        var result = ""
        var needsSpace = false
        for (piece, output) in zip(pieces, outputs) {
            let isText = piece.reading == nil
            guard !output.isEmpty else {
                needsSpace = true
                continue
            }
            if !result.isEmpty, needsSpace || (isText && piece.raw.first?.isWhitespace == true) {
                result += " "
            }
            result += output
            needsSpace = isText && piece.raw.last?.isWhitespace == true
        }
        return result
    }
}
