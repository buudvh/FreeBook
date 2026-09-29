import Foundation

/// Lối vào **hẹp** cho phần chuẩn hoá *chữ* của `TextPreprocessor`, dành cho engine **VieNeu-TTS**.
///
/// ## Vì sao không dùng thẳng `preprocess(_:)`
/// `TextPreprocessor.preprocess` chạy cả `JapaneseTransliterator` và `EnglishTransliterator` — tức nó
/// chèn **ký hiệu IPA của espeak** cho từ tiếng Anh/Nhật. Vocab của VieNeu là bộ IPA riêng của model
/// (`config.json`), nên IPA của espeak sẽ bị `encode` **bỏ im lặng**. Vì vậy engine VieNeu chỉ được dùng
/// phần biến *chữ* thành *chữ đọc được*, không dùng phần phiên âm.
///
/// ## Vì sao vẫn cần phần đọc số
/// Từ điển `sea_g2p.bin` **không có chữ số nào**: `8`, `1999`, `74`, `3`, `2002` đều không tra được, nên
/// chúng rơi vào đường **đánh vần từng ký tự** — mà vocab của model chỉ có `1 2 4 5 6 7`, thiếu `0 3 8 9`.
/// Kết quả: `8/1999` và `3/11/2002` **nuốt mất đúng 10 ký tự** (7 chữ số + 3 dấu `/`), đúng con số
/// `phoneme bỏ: 10` mà người dùng thấy. Đây là chỗ **đổi quyết định** so với plan §2 ("không chạy tiền xử
/// lý"): thực tế cho thấy bộ G2P của model không tự lo được số và ngày tháng.
///
/// ## Vì sao gọi thẳng `processVietnameseText`
/// Hàm đó đã là bộ điều phối của toàn bộ phần "chữ": `formatNumbers`, `processUnitsRangeAndRatio`,
/// `processYearRanges`, `processDates`, `processTime`, `processRomanNumerals`, cộng `precomposedString
/// WithCanonicalMapping` (chuẩn hoá NFC) và `normalizeQuotesAndDashes`. Viết lại một bản sao chỉ để lấy
/// phần số là cách chắc chắn nhất để hai bản trôi khỏi nhau — nên hai khai báo
/// (`PreprocessorRuntimeConfig`, `processVietnameseText`) được hạ từ `private` xuống `internal` **mà
/// không đổi số dòng** (`TextPreprocessor.swift` đang đúng bằng baseline 1121, luật ratchet-down cấm tăng).
///
/// Cờ `preprocessorNumericNormalizationEnabled` được `processVietnameseText` **tự kiểm** — cùng khoá
/// `UserDefaults` với đường NghiTTS, nên tắt "Chuẩn hóa cách đọc số" trong Cấu hình NghiTTS là cả hai
/// engine cùng tắt.
extension TextPreprocessor {
    /// Chuẩn hoá phần chữ trước khi đưa cho bộ G2P của VieNeu. **Idempotent về ý nghĩa**: chạy trên văn
    /// bản đã chuẩn hoá không làm hỏng thêm.
    static func normalizingForVieNeu(_ text: String) -> String {
        processVietnameseText(text, config: PreprocessorRuntimeConfig.load())
    }
}
