import SwiftUI

/// Dải tab ngang của trình duyệt bypass. Chỉ hiện khi có nhiều hơn một tab.
struct BypassBrowserTabBar: View {
    @ObservedObject var store: BypassBrowserTabStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.tabs) { tab in
                    TabPill(
                        tab: tab,
                        isActive: tab.id == store.activeTabId,
                        canClose: store.tabs.count > 1,
                        onSelect: { store.select(id: tab.id) },
                        onClose: { store.closeTab(id: tab.id) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }

    private struct TabPill: View {
        @ObservedObject var tab: BypassBrowserTab
        let isActive: Bool
        let canClose: Bool
        let onSelect: () -> Void
        let onClose: () -> Void

        var body: some View {
            HStack(spacing: 6) {
                Text(tab.displayTitle)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .leading)

                if canClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isActive ? Color.white.opacity(0.85) : .secondary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Đóng tab \(tab.displayTitle)")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, canClose ? 4 : 12)
            .padding(.vertical, 7)
            .background(isActive ? Color.blue : Color(.systemGray5))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture(perform: onSelect)
            .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        }
    }
}
