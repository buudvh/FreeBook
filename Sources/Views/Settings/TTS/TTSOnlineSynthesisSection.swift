import SwiftUI

/// Mục "TTS online" trong Cài đặt TTS (1.3.953): số lần thử lại + timeout mỗi lượt thử cho trình đọc online.
///
/// Chỉ hiện khi trình đọc chính là online (Google Cloud TTS / TTS tiện ích) — chèn ở `TTSSettingsView`.
/// Khi đã chọn giọng dự phòng offline thì hai hàng bị khoá: hiện **0** lần thử lại và **3 giây** timeout.
struct TTSOnlineSynthesisSection: View {
    @State private var retryCount = TTSOnlineSynthesisSettings.storedRetryCount
    @State private var timeoutSeconds = TTSOnlineSynthesisSettings.storedTimeoutSeconds

    private var hasFallback: Bool { TTSOnlineSynthesisSettings.hasOfflineFallback }

    var body: some View {
        Section {
            Stepper(value: retryBinding, in: TTSOnlineSynthesisSettings.retryRange) {
                HStack {
                    Text("Số lần thử lại:")
                    Spacer()
                    Text("\(hasFallback ? 0 : retryCount)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(hasFallback ? .secondary : .primary)
                }
            }
            .disabled(hasFallback)

            Stepper(value: timeoutBinding, in: TTSOnlineSynthesisSettings.timeoutRange) {
                HStack {
                    Text("Timeout mỗi lượt thử:")
                    Spacer()
                    Text("\(hasFallback ? TTSOnlineSynthesisSettings.fallbackTimeoutSeconds : timeoutSeconds) giây")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(hasFallback ? .secondary : .primary)
                }
            }
            .disabled(hasFallback)
        } header: {
            SectionHelpHeader("TTS online", paragraphs: [
                "Trình đọc online (Google Cloud TTS, TTS tiện ích) lỗi thì thử lại số lần đã đặt. Mỗi lượt thử có tối đa số giây đã đặt; hết giờ thì coi như lỗi rồi thử lượt tiếp nếu còn.",
                "Số lần thử lại chỉ áp cho đoạn đang đọc. Đoạn nạp trước thử một lần rồi bỏ.",
                "Đã chọn giọng dự phòng offline thì hai mục tự khoá: không thử lại (0) và timeout cố định 3 giây — hết giờ là chuyển sang giọng dự phòng."
            ])
        }
    }

    private var retryBinding: Binding<Int> {
        Binding(
            get: { retryCount },
            set: { newValue in
                retryCount = newValue
                TTSOnlineSynthesisSettings.storedRetryCount = newValue
            }
        )
    }

    private var timeoutBinding: Binding<Int> {
        Binding(
            get: { timeoutSeconds },
            set: { newValue in
                timeoutSeconds = newValue
                TTSOnlineSynthesisSettings.storedTimeoutSeconds = newValue
            }
        )
    }
}
