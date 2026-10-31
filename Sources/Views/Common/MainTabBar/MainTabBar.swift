import SwiftUI

/// Thanh tab của app (1.3.668) — vẽ **trong trang gốc** của từng tab qua `.mainTabBar()`, thay thanh tab hệ thống (luôn ẩn).
///
/// Lý do: ẩn/hiện thanh hệ thống bằng `.toolbar(_:for: .tabBar)` khi đẩy trang thì lúc back SwiftUI hiện thanh lại **trễ**
/// hơn trang gốc ⇒ trang gốc co lại một nhịp (cùng lỗi Reader từng gặp ở b12ddee7, khi đó sửa bằng `fullScreenCover`).
/// Thanh nằm trong trang gốc thì trang đẩy vào phủ lên nó và back là nó trượt về cùng trang gốc — không gì bật/tắt cả.
///
/// Bám dáng thanh hệ thống cũ (`configureWithDefaultBackground`): nền `.bar` mờ + vạch mảnh trên, mục đang chọn theo
/// `.tint` của `MainTabView` (trắng), mục khác xám; badge đỏ = số truyện có chương mới ở Kệ Sách.
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
                ForEach(Self.items.indices, id: \.self) { index in
                    itemButton(index)
                }
            }
            .frame(height: Self.barHeight)
        }
        .background(.bar, ignoresSafeAreaEdges: .bottom)
    }

    private func itemButton(_ index: Int) -> some View {
        let item = Self.items[index]
        let isSelected = selection == index
        let badge = index == 0 ? newChapters.totalNewBooks : 0
        return Button {
            selection = index
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 21))
                    .frame(height: 26)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 { badgeView(badge) }
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
        .accessibilityValue(badge > 0 ? "\(badge) truyện có chương mới" : "")
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
