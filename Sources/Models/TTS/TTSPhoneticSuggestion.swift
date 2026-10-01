import SwiftUI

/// Một gợi ý phiên âm ở màn thêm/sửa mục từ điển TTS.
///
/// Trước đây danh sách gợi ý là `[String]` trơn và được dựng bằng **đường khác** với lúc đọc thật:
/// nó gọi `EnglishTransliterator` (bộ luật chính tả) trong khi pipeline gọi
/// `EnglishPhonemeTransliterator` (espeak IPA), và gọi `transliterateRomaji` **vô điều kiện** thay vì
/// qua cổng `ForeignScriptClassifier`. Kết quả: với gần như mọi từ tiếng Anh, chip gợi ý khác hẳn chuỗi
/// mà TTS thực đọc. Type này gom cả nguồn gốc để hiện badge và để đường dựng gợi ý đi đúng thứ tự của
/// `TextPreprocessor.transliterateToken`.
///
/// Nguồn "từ điển" **tách làm hai** theo engine (1.3.462): `nghiTTSLibrary` (badge `NGI`) và
/// `vieNeuLibrary` (badge `VIE`). Trước đó chỉ có một case `library` (badge `TĐ`) vì màn thêm phiên âm
/// chỉ tra từ điển **của đích**; nay tra **cả hai** nên phải nói rõ chip đến từ đâu — hai từ điển độc
/// lập, cùng một cách đọc vẫn là **hai** chip khác nhau (người dùng chốt 2026-10-01).
public struct TTSPhoneticSuggestion: Identifiable, Hashable, Sendable {
    public enum Origin: String, Sendable {
        /// Lấy từ từ điển phiên âm của **NghiTTS** (`non-vietnamese-words.plist`).
        case nghiTTSLibrary
        /// Lấy từ từ điển phiên âm của **VieNeu-TTS** (`phien-am-tieng-nhat.plist`).
        case vieNeuLibrary
        /// Đường tiếng Nhật (`JapaneseTransliterator`).
        case japanese
        /// Đường tiếng Anh qua espeak IPA (`EnglishPhonemeTransliterator`, nguồn `.espeak`).
        case englishIPA
        /// Đường tiếng Anh rơi về bộ luật chính tả (espeak tắt hoặc không cho IPA).
        case englishRule

        public var badge: String {
            switch self {
            case .nghiTTSLibrary: return "NGI"
            case .vieNeuLibrary: return "VIE"
            case .japanese: return "JP"
            case .englishIPA, .englishRule: return "EN"
            }
        }

        /// `true` khi chip trỏ tới một mục **thật** trong từ điển — chỉ nhóm này mới nhấn-giữ-để-xoá được.
        /// Chip JP/EN là kết quả phiên âm tự động, không nằm trong từ điển nào nên không có gì để xoá.
        public var isDictionaryEntry: Bool {
            switch self {
            case .nghiTTSLibrary, .vieNeuLibrary: return true
            case .japanese, .englishIPA, .englishRule: return false
            }
        }

        /// Ghi chú ngắn cho VoiceOver và tooltip — nói rõ *vì sao* có gợi ý này.
        public var explanation: String {
            switch self {
            case .nghiTTSLibrary: return "Đã có trong từ điển phiên âm NghiTTS"
            case .vieNeuLibrary: return "Đã có trong từ điển phiên âm VieNeu-TTS"
            case .japanese: return "Đọc theo âm tiết tiếng Nhật"
            case .englishIPA: return "Đọc theo IPA của espeak, giống lúc TTS đọc thật"
            case .englishRule: return "Đọc theo bộ luật chính tả (espeak không cho IPA)"
            }
        }

        /// Màu badge. **Cố ý** để tất cả `.white`: `MainTabView.swift:38` đặt `.tint(.white)` toàn cục, nên
        /// đổi màu ở đây là dễ vướng bẫy "nút rỗng" đã trả giá ở 1.3.447. Hai chip thư viện phân biệt nhau
        /// bằng **chữ** `NGI` / `VIE`, đúng yêu cầu người dùng.
        public var tint: Color {
            switch self {
            case .nghiTTSLibrary, .vieNeuLibrary, .japanese, .englishIPA, .englishRule: return .white
            }
        }
    }

    public let text: String
    public let origin: Origin
    /// Chip này có phải nguồn **đáng tin** không. Với hai chip thư viện thì **cả hai** đều `true` (người
    /// dùng chốt 2026-10-01: cả hai đều là "đã có trong từ điển", không phân biệt hơn kém). Chip JP/EN chỉ
    /// `true` khi **không** từ điển nào khớp — vì lúc đó chúng mới là thứ pipeline thật sự chọn.
    public let isPipelineChoice: Bool

    public var id: String { origin.rawValue + "|" + text }

    public init(text: String, origin: Origin, isPipelineChoice: Bool) {
        self.text = text
        self.origin = origin
        self.isPipelineChoice = isPipelineChoice
    }
}
