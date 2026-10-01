import SwiftUI

/// Khối **dòng trạng thái hai công tắc** của màn từ điển phiên âm VieNeu-TTS.
///
/// Tách khỏi file chính vì trần **400 dòng**: `VieNeuJapaneseDictionaryView.swift` đang sát trần (banner tiến
/// độ ở 1.3.463 đẩy nó lên 399/400), nên mọi thứ mới phải ra file `+*.swift`.
///
/// `statusSection` **không** `private`: `listContent` ở file chính gọi nó, mà `private` của Swift giới hạn
/// theo **file** — cùng bẫy đã trả giá ở `NotificationInboxView+Merge.swift` (1.3.445).
extension VieNeuJapaneseDictionaryView {

    /// Dòng trạng thái 2 công tắc — **chỉ đọc**, không có công tắc ở màn này (chúng ở Cài đặt TTS).
    @ViewBuilder
    var statusSection: some View {
        Section {
            LabeledContent("Áp dụng từ điển", value: JapaneseFlags.dictionaryEnabled ? "Đang bật" : "Đang tắt")
            LabeledContent("Tự động phiên âm tiếng Nhật", value: JapaneseFlags.transliterationEnabled ? "Đang bật" : "Đang tắt")
        } footer: {
            if JapaneseFlags.dictionaryEnabled {
                Text("Từ khớp trong bảng này được đọc theo đúng cột phải.")
            } else {
                Text("Đang **tắt** áp dụng ⇒ thêm từ ở đây vẫn **chưa** nghe thấy khác. Bật ở **Cài đặt TTS → Quản lý riêng của trình đọc**.")
            }
        }
    }

    /// Đọc thẳng `UserDefaults` mỗi lần vẽ — hai cờ này do màn Cài đặt TTS ghi, không phải `@State` ở đây.
    private enum JapaneseFlags {
        static var dictionaryEnabled: Bool {
            UserDefaults.standard.bool(forKey: VieNeuJapanesePreprocessor.dictionaryEnabledKey)
        }
        static var transliterationEnabled: Bool {
            UserDefaults.standard.bool(forKey: VieNeuJapanesePreprocessor.japaneseTransliterationEnabledKey)
        }
    }
}
