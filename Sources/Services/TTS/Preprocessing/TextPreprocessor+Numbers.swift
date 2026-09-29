import Foundation

/// Lối vào **hẹp** cho phần chuẩn hoá *chữ* của `TextPreprocessor`, dành cho các engine **local** mà
/// vocab không tiêu thụ được phiên âm espeak IPA (hiện tại: VieNeu-TTS v3 Nano).
///
/// ## Vì sao không dùng thẳng `preprocess(_:)`
/// `TextPreprocessor.preprocess` chạy cả `JapaneseTransliterator` và `EnglishTransliterator` — tức nó
/// chèn **ký hiệu IPA của espeak** cho từ tiếng Anh/Nhật. Vocab của VieNeu là bộ IPA riêng của model
/// (`config.json`), nên IPA của espeak sẽ bị `encode` **bỏ im lặng**. Vì vậy entry này chỉ lấy phần biến
/// *chữ* thành *chữ đọc được*, không lấy phần phiên âm.
///
/// ## Vì sao vẫn cần phần đọc số
/// Từ điển `sea_g2p.bin` **không có chữ số nào**: `8`, `1999`, `74`, `3`, `2002` đều không tra được, nên
/// chúng rơi vào đường **đánh vần từng ký tự** — mà vocab của model chỉ có `1 2 4 5 6 7`, thiếu `0 3 8 9`.
/// Kết quả: `8/1999` và `3/11/2002` **nuốt mất đúng 10 ký tự**. Entry này gọi `processVietnameseText`
/// để mở rộng số/ngày/tháng trước khi đưa cho bộ G2P.
///
/// ## Vị trí gọi
/// Được gọi ở **tầng service** (`VieNeuTTSService.executeInternalSynthesis` / `…Stream`), đồng nhất với
/// NghiTTS — Piper cũng xử lý số ở service qua `preprocess`. Engine (`VieNeuTTSEngine`) không tự tiền
/// xử lý, nhận văn bản đã mở rộng số.
///
/// `PreprocessorRuntimeConfig` và `processVietnameseText` là `internal` (hạ từ `private` để entry này gọi
/// được). Cờ `preprocessorNumericNormalizationEnabled` được `processVietnameseText` **tự kiểm** — cùng
/// khoá `UserDefaults` với đường NghiTTS, nên tắt "Chuẩn hóa cách đọc số" ở Cấu hình NghiTTS là cả hai
/// engine cùng tắt.
extension TextPreprocessor {
    /// Chuẩn hoá phần chữ (số/ngày/tháng/đơn vị/la mã + NFC + dấu ngoặc) trước khi đưa cho bộ G2P của
    /// engine local không tiêu thụ được IPA espeak. **Idempotent về ý nghĩa**.
    static func normalizeVietnameseText(_ text: String) -> String {
        processVietnameseText(text, config: PreprocessorRuntimeConfig.load())
    }
}
