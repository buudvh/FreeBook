import SwiftUI

/// Gắn sheet cài đặt TTS vào widget nổi bằng binding mà SwiftUI **theo dõi được**
/// (`$ttsManager.showingSettingsSheet`), giống hành vi trước 1.3.497.
///
/// Tách thành modifier riêng để chỉ modifier này observe `TTSManager`: mỗi lần manager publish chỉ
/// modifier được đánh giá lại, còn `content` (cây widget) không bị vẽ lại theo từng nhịp phát.
///
/// Vì sao không dùng `Binding(get: { TTSManager.shared.showingSettingsSheet }, …)`: SwiftUI không thấy giá
/// trị đọc trong `get` đổi, nên nút "Xong" (`dismiss()`) ghi `false` mà sheet không đóng ⇒ `onDisappear`
/// của `TTSSettingsView` — chỗ duy nhất gọi `resumeAfterSettings()` — không chạy, TTS đứng ở trạng thái
/// tạm dừng sau khi đổi engine (log 89, 1.3.499).
struct TTSSettingsSheetHost: ViewModifier {
    @ObservedObject private var ttsManager = TTSManager.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: $ttsManager.showingSettingsSheet) {
            if let container = TTSFloatingWidgetWindowManager.shared.modelContainer {
                TTSSettingsSheet()
                    .modelContainer(container)
            } else {
                TTSSettingsSheet()
            }
        }
    }
}
