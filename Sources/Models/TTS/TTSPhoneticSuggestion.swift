import SwiftUI

/// Một gợi ý phiên âm ở màn thêm/sửa mục từ điển TTS.
///
/// Trước đây danh sách gợi ý là `[String]` trơn và được dựng bằng **đường khác** với lúc đọc thật:
/// nó gọi `EnglishTransliterator` (bộ luật chính tả) trong khi pipeline gọi
/// `EnglishPhonemeTransliterator` (espeak IPA), và gọi `transliterateRomaji` **vô điều kiện** thay vì
/// qua cổng `ForeignScriptClassifier`. Kết quả: với gần như mọi từ tiếng Anh, chip gợi ý khác hẳn chuỗi
/// mà TTS thực đọc. Type này gom cả nguồn gốc để hiện badge và để đường dựng gợi ý đi đúng thứ tự của
/// `TextPreprocessor.transliterateToken`.
public struct TTSPhoneticSuggestion: Identifiable, Hashable {
    public enum Origin: String {
        /// Lấy từ từ điển phiên âm đang có.
        case library
        /// Đường tiếng Nhật (`JapaneseTransliterator`).
        case japanese
        /// Đường tiếng Anh qua espeak IPA (`EnglishPhonemeTransliterator`, nguồn `.espeak`).
        case englishIPA
        /// Đường tiếng Anh rơi về bộ luật chính tả (espeak tắt hoặc không cho IPA).
        case englishRule

        public var badge: String {
            switch self {
            case .library: return "TĐ"
            case .japanese: return "JP"
            case .englishIPA, .englishRule: return "EN"
            }
        }

        /// Ghi chú ngắn cho VoiceOver và tooltip — nói rõ *vì sao* có gợi ý này.
        public var explanation: String {
            switch self {
            case .library: return "Đã có trong từ điển phiên âm"
            case .japanese: return "Đọc theo âm tiết tiếng Nhật"
            case .englishIPA: return "Đọc theo IPA của espeak, giống lúc TTS đọc thật"
            case .englishRule: return "Đọc theo bộ luật chính tả (espeak không cho IPA)"
            }
        }

        /// Màu badge. Ở đây chứ không ở View để màn thêm phiên âm không phình thêm dòng — file đó đang
        /// vượt baseline dòng của `check_architecture.py` và chỉ được phép giảm.
        public var tint: Color {
            switch self {
            case .library: return .blue
            case .japanese: return .pink
            case .englishIPA: return .green
            case .englishRule: return .orange
            }
        }
    }

    public let text: String
    public let origin: Origin
    /// Đường mà pipeline **sẽ thật sự chọn** cho từ này. Chip đó được làm nổi.
    public let isPipelineChoice: Bool

    public var id: String { origin.rawValue + "|" + text }

    public init(text: String, origin: Origin, isPipelineChoice: Bool) {
        self.text = text
        self.origin = origin
        self.isPipelineChoice = isPipelineChoice
    }
}
