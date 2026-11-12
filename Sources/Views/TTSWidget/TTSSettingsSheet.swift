import SwiftUI

/// Sheet toàn cục dùng chung giữa Widget TTS và mọi màn hình.
/// Bọc TTSSettingsView trong NavigationStack để NavigationLink
/// bên trong hoạt động đúng như khi điều hướng từ Settings tab.
struct TTSSettingsSheet: View {
    @ObservedObject private var ttsManager = TTSManager.shared

    var body: some View {
        NavigationStack {
            TTSSettingsView(isPresentedAsSheet: true)
        }
        .presentationDragIndicator(.visible) // không còn nút "Xong" (1.3.641) — vuốt xuống để đóng
        // Mở được từ widget TTS (cửa sổ riêng, không thừa hưởng `.tint` của `MainTabView`) ⇒ tự gắn màu nhấn.
        .appAccentTint()
        // Vỏ sheet chỉ biến mất khi **sheet đóng thật** — vào trang con trong `NavigationStack` thì vỏ vẫn còn. Đây là
        // chỗ báo kết thúc phiên Cài đặt cho **mọi** lối mở sheet (1.3.907): nút ⚙ của sheet Hẹn giờ
        // (`TTSSettingsSheetHost`, có thêm `onDismiss`) lẫn nút "Giọng đọc" của sheet đĩa nghe (`TTSQuickControlSheet`,
        // `.sheet` riêng, không có `onDismiss` của host). Trước đây chỉ dựa `isPresented` ở màn gốc của sheet, mà cờ
        // đó vẫn `true` lúc sheet đóng ⇒ phiên kẹt ở "đang mở" ⇒ lần mở sau không dừng đọc.
        .onDisappear { TTSSettingsPauseSession.finish(caller: "TTSSettingsSheet.onDisappear") }
    }
}
