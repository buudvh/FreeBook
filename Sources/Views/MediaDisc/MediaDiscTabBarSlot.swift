import SwiftUI

/// Ô **giữa** của `MainTabBar` (1.3.812): thanh tab luôn 5 ô (Kệ Sách · Khám Phá · [ô này] · Tiện Ích · Cài Đặt) để icon các
/// tab không bao giờ đổi chỗ. Có nguồn đĩa (`MediaDiscWindowManager.kind` — nhạc có album, hoặc TTS có phiên + kiểu "Đĩa góc
/// dưới") ⇒ đĩa 32 pt (`MediaDiscFaceButton(.tabBar)`), chạm mở sheet điều khiển nhanh; không có ⇒ ô trống, không bấm được.
///
/// Có đĩa hay không đọc thẳng **trạng thái phát** của manager ⇒ đúng ngay từ khung hình đầu, không chờ đầu dò. View riêng
/// để chỉ ô này vẽ lại theo manager, thân `MainTabBar` thì không.
struct MediaDiscTabBarSlot: View {
    @ObservedObject private var manager = MediaDiscWindowManager.shared

    var body: some View {
        ZStack {
            if manager.kind != nil {
                MediaDiscFaceButton(style: .tabBar)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: manager.kind)
    }
}
