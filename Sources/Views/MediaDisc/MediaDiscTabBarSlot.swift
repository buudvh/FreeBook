import SwiftUI

/// Ô **giữa** của `MainTabBar` (1.3.812): thanh tab luôn 5 ô (Kệ Sách · Khám Phá · [ô này] · Tiện Ích · Cài Đặt) để icon các
/// tab không bao giờ đổi chỗ. Có nguồn đĩa (`MediaDiscWindowManager.kind` — nhạc có album, hoặc TTS có phiên + kiểu "Đĩa góc
/// dưới") ⇒ đĩa (`MediaDiscFaceButton(.tabBar)`), chạm mở sheet điều khiển nhanh; không có ⇒ ô trống, không bấm được.
///
/// Dáng (1.3.814, anh Bửu chọn): bìa 44 pt có **mép dưới ngang chân chữ** của các tab, đặt giữa một vòng nền 52 pt cùng
/// chất liệu thanh (`.bar`) có viền mảnh như vạch trên của thanh ⇒ nhô lên khỏi thanh khoảng 5,5 pt thành một gờ tròn.
/// Vòng nền chỉ vẽ **phần nhô** trên thanh (`.mask`), phần trong thanh để nền của thanh lo — không chồng hai lớp `.bar`.
///
/// Có đĩa hay không đọc thẳng **trạng thái phát** của manager ⇒ đúng ngay từ khung hình đầu, không chờ đầu dò. View riêng
/// để chỉ ô này vẽ lại theo manager, thân `MainTabBar` thì không.
struct MediaDiscTabBarSlot: View {
    /// Bằng đĩa góc và vùng chạm của `MediaDiscFaceButton(.tabBar)`.
    private static let ringSize: CGFloat = MediaDiscPlacement.discSize
    /// Chân chữ tab cách mép trên thanh: cụm icon 26 + khe 3 + chữ 10 pt (~12) cao ~41 pt canh giữa thanh 49 pt ⇒ chữ từ
    /// ~33 tới ~45, đường chân chữ ~42,5. Đổi cỡ icon / chữ của `MainTabBar` thì đo lại số này.
    private static let discBottomFromBarTop: CGFloat = 42.5

    @ObservedObject private var manager = MediaDiscWindowManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            if manager.kind != nil {
                disc
                    .transition(.scale(scale: 0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: manager.kind)
    }

    /// Khung vòng nền 52 pt; mép trên đặt cao hơn mép trên thanh đúng phần nhô.
    private var disc: some View {
        ZStack {
            ringCap
            MediaDiscFaceButton(style: .tabBar)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .offset(y: -Self.protrusion)
    }

    /// Phần vòng nền nhô trên thanh: cùng `.bar` + viền vạch ngăn, cắt đúng phần nằm trên mép thanh.
    private var ringCap: some View {
        ZStack {
            Circle().fill(.bar)
            Circle().stroke(Color(uiColor: .separator), lineWidth: 0.5)
        }
        .mask(alignment: .top) {
            Rectangle().frame(height: Self.protrusion)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Vòng nền nhô khỏi mép trên thanh: (52 − 44) / 2 + (44 − 42,5) = 5,5 pt.
    private static var protrusion: CGFloat {
        (ringSize - MediaDiscFaceButton.coverSize) / 2 + (MediaDiscFaceButton.coverSize - discBottomFromBarTop)
    }
}
