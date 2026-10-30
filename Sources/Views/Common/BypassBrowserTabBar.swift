import SwiftUI

/// Dải tab viên thuốc của trình duyệt người dùng (mockup 2026-10-30): **luôn hiện** dưới header, kể cả khi chỉ có 1 tab.
///
/// - Viên cao 32, rộng tối đa 148; tab đang chọn kiểu chip (nền 18%, viền 60%, chữ đậm). Màu dựa trên `.primary` ⇒ ở
///   giao diện tối đúng màu trắng của mockup, ở giao diện sáng vẫn đọc được.
/// - ✕ trên mỗi tab; chỉ 1 tab ⇒ ẩn ✕ (store không cho đóng tab cuối).
/// - Nút "+" tròn 32 nằm **ngay sau tab cuối** trong cùng dải cuộn, mờ khi đã đủ `BypassBrowserTabStore.maxTabCount`.
/// - Chọn tab ⇒ dải cuộn tới tab đó; thêm tab (kể cả tab mở nền) ⇒ dải cuộn tới cuối. Cuộn hoãn một vòng runloop:
///   `scrollTo` tới id vừa chèn trong cùng lượt cập nhật thường không có tác dụng.
struct BypassBrowserTabBar: View {
    @ObservedObject var store: BypassBrowserTabStore
    let onNewTab: () -> Void

    private static let addButtonId = "browser-tab-strip-add"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.tabs) { tab in
                        TabPill(
                            tab: tab,
                            isActive: tab.id == store.activeTabId,
                            canClose: store.tabs.count > 1,
                            onSelect: { store.select(id: tab.id) },
                            onClose: { store.closeTab(id: tab.id) }
                        )
                        .id(tab.id)
                    }
                    addButton
                        .id(Self.addButtonId)
                }
                .padding(.horizontal, 10)
            }
            .padding(.bottom, 8)
            .onAppear {
                scroll(proxy, to: store.activeTabId, anchor: .center, animated: false)
            }
            .onChange(of: store.activeTabId) { _, newId in
                scroll(proxy, to: newId, anchor: .center)
            }
            .onChange(of: store.tabs.count) { oldCount, newCount in
                guard newCount > oldCount else { return }
                scroll(proxy, to: Self.addButtonId, anchor: .trailing)
            }
        }
    }

    private var addButton: some View {
        Button(action: onNewTab) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!store.canOpenMoreTabs)
        .opacity(store.canOpenMoreTabs ? 1 : 0.35)
        .accessibilityLabel("Tab mới")
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String, anchor: UnitPoint, animated: Bool = true) {
        guard !id.isEmpty else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: anchor)
                }
            } else {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
    }

    private struct TabPill: View {
        @ObservedObject var tab: BypassBrowserTab
        let isActive: Bool
        let canClose: Bool
        let onSelect: () -> Void
        let onClose: () -> Void

        /// Mockup: viên rộng tối đa 148 = đệm trái 12 + chữ + khoảng 4 + ô ✕ 30 (đệm phải 0); không ✕ ⇒ đệm phải 12.
        private static let maxPillWidth: CGFloat = 148
        private static let closeWidth: CGFloat = 30

        private var maxTitleWidth: CGFloat {
            canClose ? Self.maxPillWidth - 12 - 4 - Self.closeWidth : Self.maxPillWidth - 24
        }

        var body: some View {
            HStack(spacing: 4) {
                BrowserCappedWidthLayout(maxWidth: maxTitleWidth) {
                    Text(tab.displayTitle)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if canClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.primary.opacity(isActive ? 0.9 : 0.6))
                            .frame(width: Self.closeWidth, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Đóng tab \(tab.displayTitle)")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, canClose ? 0 : 12)
            .frame(height: 32)
            .background(Capsule().fill(Color.primary.opacity(isActive ? 0.18 : 0.08)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isActive ? 0.6 : 0), lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture(perform: onSelect)
            .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        }
    }
}
