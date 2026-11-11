import SwiftUI

/// Gắn sheet cài đặt TTS bằng binding mà SwiftUI **theo dõi được** (`$ttsManager.showingSettingsSheet`), giống hành vi
/// trước 1.3.497. Từ 1.3.713 gắn trong sheet Hẹn giờ (`TTSQuickTimerSheet`, lối vào duy nhất qua nút ⚙) để Cài đặt mở
/// đè lên nó ngay; trước đó gắn ở widget nổi nên phải đóng Hẹn giờ, chờ 0,3 s rồi mới mở.
///
/// Tách thành modifier riêng để chỉ modifier này observe `TTSManager`: mỗi lần manager publish chỉ
/// modifier được đánh giá lại, còn `content` không bị vẽ lại theo từng nhịp phát.
///
/// Vì sao không dùng `Binding(get: { TTSManager.shared.showingSettingsSheet }, …)`: SwiftUI không thấy giá
/// trị đọc trong `get` đổi, nên nút "Xong" cũ (`dismiss()`, bỏ ở 1.3.641) ghi `false` mà sheet không đóng ⇒ `onDisappear`
/// của `TTSSettingsView` — chỗ duy nhất gọi `resumeAfterSettings()` — không chạy, TTS đứng ở trạng thái
/// tạm dừng sau khi đổi engine (log 89, 1.3.499).
struct TTSSettingsSheetHost: ViewModifier {
    @ObservedObject private var ttsManager = TTSManager.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: $ttsManager.showingSettingsSheet) {
            if let container = MediaDiscWindowManager.shared.modelContainer {
                TTSSettingsSheet()
                    .modelContainer(container)
            } else {
                TTSSettingsSheet()
            }
        }
    }
}
