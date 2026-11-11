import SwiftUI

/// Thanh tab của app (1.3.668) — vẽ **trong trang gốc** của từng tab qua `.mainTabBar()`, thay thanh tab hệ thống (luôn ẩn).
///
/// Lý do: ẩn/hiện thanh hệ thống bằng `.toolbar(_:for: .tabBar)` khi đẩy trang thì lúc back SwiftUI hiện thanh lại **trễ**
/// hơn trang gốc ⇒ trang gốc co lại một nhịp (cùng lỗi Reader từng gặp ở b12ddee7, khi đó sửa bằng `fullScreenCover`).
/// Thanh nằm trong trang gốc thì trang đẩy vào phủ lên nó và back là nó trượt về cùng trang gốc — không gì bật/tắt cả.
///
/// Bám dáng thanh hệ thống cũ (`configureWithDefaultBackground`): nền `.bar` mờ + vạch mảnh trên, mục đang chọn theo
/// `.tint` của `MainTabView` (màu nhấn người dùng chọn, `appAccentTint()`), mục khác xám; badge đỏ = số truyện có chương mới ở Kệ Sách.
///
/// **Luôn 5 ô** (1.3.812): Kệ Sách · Khám Phá · [ô giữa] · Tiện Ích · Cài Đặt. Ô giữa là đĩa nghe 44 pt có gờ nền nhô lên (1.3.814) khi có nhạc / TTS
/// (`MediaDiscTabBarSlot`); không nghe ⇒ đĩa xám đứng yên, không bấm được (1.3.821) — icon các tab không
/// bao giờ đổi chỗ.
struct MainTabBar: View {
    struct Item {
        let title: String
        let systemImage: String

        /// Nhãn cho `.tabItem` của `MainTabView` (thanh hệ thống ẩn, nhưng `TabView` vẫn cần đủ 4 tab).
        var label: some View { Label(title, systemImage: systemImage) }
    }

    /// Thứ tự = `tag` của tab trong `MainTabView`.
    static let items: [Item] = [
        Item(title: "Kệ Sách", systemImage: "books.vertical.fill"),
        Item(title: "Khám Phá", systemImage: "safari.fill"),
        Item(title: "Tiện Ích", systemImage: "puzzlepiece.extension.fill"),
        Item(title: "Cài Đặt", systemImage: "gearshape.fill")
    ]

    static let barHeight: CGFloat = 49

    @Binding var selection: Int
    @ObservedObject private var newChapters = NewChapterInboxManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                itemButton(0)
                itemButton(1)
                MediaDiscTabBarSlot()
                itemButton(2)
                itemButton(3)
            }
            .frame(height: Self.barHeight)
        }
        .background(.bar, ignoresSafeAreaEdges: .bottom)
    }

    private func itemButton(_ index: Int) -> some View {
        let item = Self.items[index]
        let isSelected = selection == index
        let badge = index == 0 ? newChapters.totalNewBooks : 0
        // Tab Cài Đặt: chấm đỏ khi có bản app mới chưa xem (`AppUpdateRepository`).
        let showsUpdateDot = index == 3 && AppUpdateRepository.shared.showsUnseenDot
        return Button {
            selection = index
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 21))
                    .frame(height: 26)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            badgeView(badge)
                        } else if showsUpdateDot {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -1)
                        }
                    }
                Text(item.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(uiColor: .systemGray)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(badge > 0 ? "\(badge) truyện có chương mới" : (showsUpdateDot ? "Có bản cập nhật" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func badgeView(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(Color.red))
            .fixedSize()
            .offset(x: 12, y: -5)
    }
}
