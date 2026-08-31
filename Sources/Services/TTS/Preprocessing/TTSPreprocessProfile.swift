import Foundation

/// Hồ sơ tiền xử lý văn bản, chọn theo engine sẽ đọc.
///
/// Tồn tại vì hai engine on-device cần **hai** cách chuẩn bị text khác nhau ở đúng một điểm: phiên
/// âm chữ Latin.
///
/// - `piper`: Piper chỉ có bộ âm vị tiếng Việt, nên từ tiếng Anh phải được phiên âm sang dạng đọc
///   được bằng tiếng Việt trước (`EnglishPhonemeTransliterator`). Không làm thì Piper đọc sai hoặc bỏ chữ.
/// - `vieneu`: VieNeu-TTS đọc **tiếng Anh gốc** qua sea-g2p với code-switching Việt–Anh. Phiên âm
///   trước là phá: "Hello" biến thành "hê lô" rồi bị phiên âm lần nữa theo âm Việt.
///
/// Những gì **cả hai** đều cần và không được tắt theo hồ sơ:
///
/// - Chuẩn hoá số/ngày/giờ/tiền/phần trăm. Với VieNeu điều này còn **bắt buộc** hơn: bộ ký hiệu
///   phoneme của sea-g2p dùng chữ số làm **dấu thanh** (`aː2`, `a6j`, `iɛ6n`), nên một chữ số thô lọt
///   xuống G2P sẽ bị model đọc thành thanh điệu.
/// - Chuyển Hiragana/Katakana sang Romaji. sea-g2p chỉ có Việt/Thái/Indo cộng tiếng Anh, **không có
///   tiếng Nhật**, nên chữ Nhật vẫn phải đi qua `JapaneseTransliterator`.
/// - Từ điển thay thế của người dùng. Đó là ý định tường minh của người dùng, hồ sơ nào cũng tôn trọng.
enum TTSPreprocessProfile: String, Sendable {
    case piper
    case vieneu

    /// Có phiên âm chữ Latin sang dạng đọc bằng tiếng Việt hay không.
    var appliesLatinTransliteration: Bool {
        switch self {
        case .piper: return true
        case .vieneu: return false
        }
    }
}
