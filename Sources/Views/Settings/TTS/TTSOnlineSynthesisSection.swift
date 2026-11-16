import SwiftUI

/// Mục "TTS online" trong Cài đặt TTS (1.3.953): số lần thử lại + timeout mỗi lượt thử cho trình đọc online.
///
/// Chỉ hiện khi trình đọc chính là online (Google Cloud TTS / TTS tiện ích) — chèn ở `TTSSettingsView`.
/// Đã chọn giọng dự phòng offline (1.3.960): hàng thử lại khoá ở **1** lần, timeout vẫn sửa được (xem
/// `TTSOnlineSynthesisSettings`).
struct TTSOnlineSynthesisSection: View {
    @State private var retryCount = TTSOnlineSynthesisSettings.storedRetryCount
    @State private var timeoutSeconds = TTSOnlineSynthesisSettings.storedTimeoutSeconds
    /// Đọc qua `@AppStorage` để chọn / bỏ giọng dự phòng ở màn "Giọng dự phòng" rồi quay lại là mục này vẽ lại ngay —
    /// đọc thẳng `UserDefaults` trong `body` thì không ai báo đổi (1.3.960).
    @AppStorage(TTSOnlineFallbackSettings.toolKey) private var fallbackTool = ""

    private var hasFallback: Bool { TTSOnlineFallbackSettings.Engine(rawValue: fallbackTool) != nil }

    var body: some View {
        Section {
            Stepper(value: retryBinding, in: TTSOnlineSynthesisSettings.retryRange) {
                HStack {
                    Text("Số lần thử lại:")
                    Spacer()
                    Text("\(hasFallback ? TTSOnlineSynthesisSettings.fallbackRetryCount : retryCount)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(hasFallback ? .secondary : .primary)
                }
            }
            .disabled(hasFallback)

            Stepper(value: timeoutBinding, in: TTSOnlineSynthesisSettings.timeoutRange) {
                HStack {
                    Text("Timeout mỗi lượt thử:")
                    Spacer()
                    Text("\(timeoutSeconds) giây")
                        .font(.system(.body, design: .monospaced))
                }
            }
        } header: {
            SectionHelpHeader("TTS online", paragraphs: [
                "Trình đọc online (Google Cloud TTS, TTS tiện ích) lỗi thì thử lại số lần đã đặt. Mỗi lượt thử có tối đa số giây đã đặt; hết giờ thì coi như lỗi rồi thử lượt tiếp nếu còn.",
                "Không có giọng dự phòng: số lần thử lại chỉ áp cho đoạn đang đọc, đoạn nạp trước thử một lần rồi bỏ.",
                "Đã chọn giọng dự phòng offline: thử lại cố định 1 lần, áp cho cả đoạn nạp trước. Đoạn đang đọc quá 3 giây chưa có tiếng thì app đọc song song bằng giọng dự phòng — bên nào xong trước phát bên đó. Chỉ khi online hết lượt thử hoặc máy mất mạng mới chuyển hẳn sang giọng dự phòng."
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
