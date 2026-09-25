import SwiftUI

/// Giao diện Home Native của Trình duyệt Bypass theo thiết kế dark theme:
/// Truy cập nhanh (lưới 4x3 trượt phân trang) và Lịch sử truy cập (10 card gần nhất + Xem thêm).
public struct BypassBrowserHomeView: View {
    public let installedExtensions: [Extension]
    public let onSelectUrl: (String) -> Void
    public let onOpenAllHistory: () -> Void

    @State private var recentHistory: [BrowserHistoryStore.Item] = []
    @State private var currentPageIndex: Int = 0
    @State private var showingClearHistoryAlert: Bool = false

    public init(
        installedExtensions: [Extension] = [],
        onSelectUrl: @escaping (String) -> Void,
        onOpenAllHistory: @escaping () -> Void
    ) {
        self.installedExtensions = installedExtensions
        self.onSelectUrl = onSelectUrl
        self.onOpenAllHistory = onOpenAllHistory
    }

    private struct QuickShortcut: Identifiable {
        let id = UUID()
        let name: String
        let url: String
        let iconName: String
        let isSystemIcon: Bool
    }

    private var allShortcuts: [QuickShortcut] {
        var list: [QuickShortcut] = []

        // Tiện ích đã cài đặt
        for ext in installedExtensions where ext.isEnabled {
            let src = ext.sourceUrl.isEmpty ? "https://www.google.com" : ext.sourceUrl
            list.append(QuickShortcut(
                name: ext.name,
                url: src,
                iconName: "puzzlepiece.extension.fill",
                isSystemIcon: true
            ))
        }

        // Các trang mặc định phổ biến
        let defaultSites: [(name: String, url: String, icon: String)] = [
            ("Google", "https://www.google.com", "magnifyingglass"),
            ("YouTube", "https://www.youtube.com", "play.rectangle.fill"),
            ("Bing", "https://www.bing.com", "b.circle.fill"),
            ("Baidu", "https://www.baidu.com", "pawprint.fill"),
            ("Bilibili", "https://www.bilibili.com", "tv.fill"),
            ("Weibo", "https://weibo.com", "bubble.left.and.bubble.right.fill"),
            ("Zhihu", "https://www.zhihu.com", "questionmark.circle.fill"),
            ("Wikipedia", "https://vi.wikipedia.org", "character.book.closed.fill"),
            ("Dịch GG", "https://translate.google.com", "globe.badge.chevron.backward"),
            ("Tangthuvien", "https://truyen.tangthuvien.vn", "book.fill"),
            ("Qidian", "https://www.qidian.com", "flame.fill"),
            ("69shu", "https://www.69shu.me", "bookmark.fill")
        ]

        for site in defaultSites {
            if !list.contains(where: { $0.url == site.url }) {
                list.append(QuickShortcut(
                    name: site.name,
                    url: site.url,
                    iconName: site.icon,
                    isSystemIcon: true
                ))
            }
        }

        return list
    }

    private var shortcutPages: [[QuickShortcut]] {
        let items = allShortcuts
        let pageSize = 12
        return stride(from: 0, to: items.count, by: pageSize).map {
            Array(items[$0..<min($0 + pageSize, items.count)])
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Khối Truy cập nhanh
                VStack(spacing: 12) {
                    sectionCapsuleHeader("Truy cập nhanh")

                    // Lưới phím tắt phân trang
                    if !shortcutPages.isEmpty {
                        TabView(selection: $currentPageIndex) {
                            ForEach(shortcutPages.indices, id: \.self) { pageIdx in
                                let pageItems = shortcutPages[pageIdx]
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                                    spacing: 16
                                ) {
                                    ForEach(pageItems) { item in
                                        Button(action: {
                                            onSelectUrl(item.url)
                                        }) {
                                            VStack(spacing: 6) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 14)
                                                        .fill(Color(white: 0.14))
                                                        .frame(width: 50, height: 50)

                                                    Image(systemName: item.iconName)
                                                        .font(.system(size: 20))
                                                        .foregroundColor(.white)
                                                }

                                                Text(item.name)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(Color(white: 0.85))
                                                    .lineLimit(1)
                                                    .frame(maxWidth: 68)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .tag(pageIdx)
                            }
                        }
                        .frame(height: 250)
                        .tabViewStyle(.page(indexDisplayMode: .never))

                        // Page indicator
                        if shortcutPages.count > 1 {
                            HStack(spacing: 6) {
                                ForEach(shortcutPages.indices, id: \.self) { idx in
                                    if idx == currentPageIndex {
                                        Capsule()
                                            .fill(Color.blue)
                                            .frame(width: 16, height: 6)
                                    } else {
                                        Circle()
                                            .fill(Color.gray.opacity(0.4))
                                            .frame(width: 6, height: 6)
                                    }
                                }
                            }
                            .padding(.top, -6)
                        }
                    }
                }

                // Header Khối Lịch sử truy cập
                VStack(spacing: 14) {
                    sectionCapsuleHeader("Lịch sử truy cập")

                    // Hàng nút phụ: Xóa lịch sử và Xem thêm
                    HStack {
                        Button(action: {
                            showingClearHistoryAlert = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Xóa lịch sử")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.12))
                            .cornerRadius(8)
                        }
                        .disabled(recentHistory.isEmpty)

                        Spacer()

                        Button(action: onOpenAllHistory) {
                            HStack(spacing: 4) {
                                Text("Xem thêm")
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 16)

                    // 10 card gần nhất
                    if recentHistory.isEmpty {
                        VStack(spacing: 8) {
                            Text("Chưa có lịch sử duyệt web nào")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(recentHistory.prefix(10)) { item in
                                Button(action: {
                                    onSelectUrl(item.urlString)
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.yellow)
                                            .frame(width: 28, height: 28)
                                            .background(Color.yellow.opacity(0.12))
                                            .clipShape(Circle())

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Text(item.urlString)
                                                .font(.system(size: 11))
                                                .foregroundColor(.gray)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 11))
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color(white: 0.12))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color.black.ignoresSafeArea())
        .alert("Xác nhận xóa lịch sử", isPresented: $showingClearHistoryAlert) {
            Button("Xóa toàn bộ", role: .destructive) {
                BrowserHistoryStore.shared.clearAll()
                recentHistory = []
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Toàn bộ lịch sử duyệt web sẽ bị xóa vĩnh viễn.")
        }
        .onAppear {
            reloadHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: BrowserHistoryStore.didChangeNotification)) { _ in
            reloadHistory()
        }
    }

    private func sectionCapsuleHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(white: 0.16))
            .clipShape(Capsule())
    }

    private func reloadHistory() {
        recentHistory = BrowserHistoryStore.shared.load()
    }
}
