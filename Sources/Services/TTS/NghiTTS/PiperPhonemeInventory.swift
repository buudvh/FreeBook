import Foundation

/// Bộ ký hiệu âm vị mà **model Piper đang dùng** thật sự nhận, đọc từ `phoneme_id_map` trong
/// `<giọng>.onnx.json`.
///
/// Tồn tại vì một phát hiện đo được, đi ngược lại giả định của 1.3.290 và 1.3.291: bảng này **không
/// phải** bộ âm vị tiếng Việt mà là **bộ IPA đầy đủ 161 ký hiệu**, gồm mọi thứ espeak `en-us` sinh ra
/// (`æ ð θ ŋ ɑ ɔ ɛ ə ɚ ɜ ɝ ɪ ʊ ʌ ʃ ʒ ɹ ɫ ɾ ᵻ ɐ ˈ ˌ ː`) và mọi thứ tiếng Nhật cần (`ɕ ʑ ɸ ɲ ŋ ɾ ː`).
///
/// Hệ quả: đưa IPA tiếng Anh **thẳng** vào chuỗi phoneme là hợp lệ về mặt từ vựng, không cần vòng
/// "IPA → chữ Việt → text → phiên âm lại".
///
/// **Nhưng có mặt trong từ vựng không có nghĩa là đã được train.** 161 ký hiệu này là bảng chuẩn mà
/// Piper phát cho *mọi* giọng, không phải bằng chứng dữ liệu huấn luyện tiếng Việt có chứa `θ` hay `æ`.
/// Đó là lý do màn Thử phiên âm có ô nhập IPA thô: phải **nghe** trước khi tin.
struct PiperPhonemeInventory {
    /// Ký hiệu → id. Giữ cả id để dùng lại được cho đường tổng hợp.
    let symbolToID: [String: [Int]]

    var count: Int { symbolToID.count }

    private struct VoiceConfig: Decodable {
        let phoneme_id_map: [String: [Int]]?
    }

    init(configURL: URL) throws {
        let data = try Data(contentsOf: configURL)
        guard let map = try JSONDecoder().decode(VoiceConfig.self, from: data).phoneme_id_map,
              !map.isEmpty else {
            throw TTSError.internalError("\(configURL.lastPathComponent) không có phoneme_id_map")
        }
        self.symbolToID = map
    }

    func contains(_ symbol: String) -> Bool {
        symbolToID[symbol] != nil
    }

    func ids(for symbol: String) -> [Int]? {
        symbolToID[symbol]
    }

    /// Các scalar trong `ipa` mà model **không** nhận, kèm số lần xuất hiện, sắp theo tần suất giảm.
    ///
    /// Đây là phép đo biến chỗ mất chữ vô hình thành con số: trước đây `ONNXPiperEngine` bỏ im lặng
    /// từng scalar lạ và chỉ ghi một dòng log mỗi lần, nên không ai đếm được tổng thiệt hại.
    func missingScalars(in ipa: String) -> [(symbol: String, count: Int)] {
        var tally: [String: Int] = [:]
        for scalar in ipa.unicodeScalars {
            let symbol = String(scalar)
            if symbolToID[symbol] == nil {
                tally[symbol, default: 0] += 1
            }
        }
        return tally
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map { (symbol: $0.key, count: $0.value) }
    }

    /// Ký hiệu thay thế **trong** inventory cho một scalar không có.
    ///
    /// Bảng này được gieo từ chính phép đo inventory 161 ký hiệu, không phải đoán: mỗi dòng là một
    /// ký hiệu espeak hoặc bảng IPA Nhật có thể sinh ra mà bảng của model không có.
    ///
    /// Trả `""` nghĩa là **bỏ có chủ ý** (ký hiệu chỉ mang thông tin nối, không mang âm). Trả `nil`
    /// nghĩa là chưa biết — caller phải đếm và ghi log để lần sau bổ sung được đúng chỗ.
    static func downgrade(_ symbol: String) -> String? {
        switch symbol {
        // Phụ âm mũi uvular của tiếng Nhật (moraic n) — không có trong bảng, hạ về `n`.
        case "ɴ": return "n"
        // Affricate viết liền một ký tự → viết rời hai scalar, cả hai đều có trong bảng.
        case "ʧ": return "tʃ"
        case "ʤ": return "dʒ"
        case "ʨ": return "tɕ"
        case "ʥ": return "dʑ"
        case "ʦ": return "ts"
        // Dấu nối (tie bar) và dấu nhấn phụ chỉ mang thông tin ghép, không mang âm.
        case "\u{0361}", "\u{035C}", "\u{02BC}", "\u{02C8}": return ""
        // Ranh giới cụm của espeak → dùng ký hiệu ngắt mà bảng có.
        case "|", "‖", "\u{203F}": return "_"
        // Chỉ số trên của phụ âm mũi → phụ âm thường.
        case "ᵐ": return "m"
        case "ⁿ": return "n"
        default: return nil
        }
    }
}
