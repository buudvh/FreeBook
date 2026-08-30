import Foundation

/// Phiên âm một từ **tiếng Anh** bằng cách hỏi espeak-ng lấy IPA rồi map sang âm tiết Việt.
///
/// Đây là đường chính từ 1.3.290; bộ luật chính tả `EnglishTransliterator` tụt xuống **dự phòng** cho
/// ba trường hợp: espeak chưa khởi tạo được, giọng `en-us` không có trong bộ dữ liệu đã đóng gói, hoặc
/// IPA trả về không dựng nổi âm tiết nào.
///
/// Vì sao làm được mà không thêm dependency: `.github/workflows/build-ipa.yml` khi dọn dữ liệu espeak
/// giữ lại **cả `en_dict`** và thư mục `voices/en` (chỉ xoá các ngôn ngữ khác), nên từ điển phát âm
/// tiếng Anh đã nằm trong IPA. Trước đây code chỉ đặt giọng `vi` một lần rồi chốt cờ nên không ai dùng
/// tới nó.
///
/// Cache: không giữ cache riêng ở đây. `TextPreprocessor.transliterationCache` đã cache theo token và
/// bị xoá mỗi khi từ điển đổi, thêm một tầng nữa chỉ tạo hai nguồn sự thật.
enum EnglishPhonemeTransliterator {

    /// Bật/tắt đường IPA để so A/B ngay trên máy. Khoá lower-camel-case để `BackupSettingsArchiver`
    /// tự sao lưu như các khoá cấu hình khác.
    static let useEspeakKey = "ttsEnglishPhonemeTransliterationEnabled"

    static var isEspeakPathEnabled: Bool {
        UserDefaults.standard.object(forKey: useEspeakKey) as? Bool ?? true
    }

    /// Kết quả một lượt phiên âm, để màn thử nghiệm nói được **đường nào** đã chạy.
    struct Outcome {
        enum Source: String {
            case espeak = "espeak IPA"
            case ruleFallback = "bộ luật chính tả"
        }

        let text: String
        let source: Source
        let ipa: String
    }

    /// API dùng ở pipeline: chỉ cần chuỗi kết quả.
    static func transliterate(_ word: String) -> String {
        detailed(word).text
    }

    static func detailed(_ word: String) -> Outcome {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(text: "", source: .ruleFallback, ipa: "")
        }

        guard isEspeakPathEnabled else {
            return Outcome(text: EnglishTransliterator.transliterateWord(trimmed), source: .ruleFallback, ipa: "")
        }

        let ipa = (try? EspeakPhonemizer.phonemizeEnglish(text: trimmed)) ?? ""
        if !ipa.isEmpty {
            let mapped = IPAToVietnameseMapper.transliterate(ipa: ipa)
            if !mapped.isEmpty {
                return Outcome(text: mapped, source: .espeak, ipa: ipa)
            }
        }

        return Outcome(
            text: EnglishTransliterator.transliterateWord(trimmed),
            source: .ruleFallback,
            ipa: ipa
        )
    }
}
