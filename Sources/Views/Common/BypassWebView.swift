import SwiftUI
import WebKit

/// Trình duyệt người dùng (mockup 2026-10-30 "Trình duyệt mới", thanh dưới sát đáy 2026-10-31):
/// - Header gọn: `.pageTitle(tiêu đề trang)` (đã dịch khi trang đang dịch QT) + "Xong".
/// - Dải tab viên thuốc luôn hiện (`BypassBrowserTabBar`) + vạch tiến độ 2pt (`BrowserLoadProgressLine`).
/// - Trang (web hoặc Home) chiếm phần giữa và **kết thúc ngay trên thanh dưới** (không bị che); dải báo tự dịch nổi
///   ở đầu trang, dải báo popup bị chặn nổi ở cuối trang.
/// - Thanh dưới gắn sát đáy (`BrowserBottomBar`): lùi, tiến, ô URL, nút Import, nút ⋮ mở ngăn kéo.
///
/// Thành phần giao diện ở `Sources/Views/Common/Browser/Chrome/`; thao tác (tab, Home, nạp URL, import, sao chép link)
/// ở `BypassWebView+Actions`. Menu nhấn giữ / sheet dịch-tra / bảng chia sẻ do phần menu nhấn giữ gắn thêm.
struct BypassWebView: View {
    let urlString: String
    let host: String?
    /// Ép UA/chế độ điện thoại cho mọi tab của phiên này (bỏ qua chế độ máy tính theo tên miền, không ghi đè tuỳ chọn
    /// đã lưu) — dùng khi mở từ nút "Mở link lỗi" để clearance khớp UA của `fetch`. Xem `BypassBrowserTabStore+MobileOverride`.
    /// Bật thì `urlString` http(s) tuyệt đối được mở nguyên văn (không qua `cleanAndResolveUrl`) — xem `resolvedUrl`.
    let forcesMobileUserAgent: Bool
    var onImport: ((_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void)? = nil

    init(
        urlString: String,
        host: String? = nil,
        forcesMobileUserAgent: Bool = false,
        onImport: ((_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void)? = nil
    ) {
        self.urlString = urlString
        self.host = host
        self.forcesMobileUserAgent = forcesMobileUserAgent
        self.onImport = onImport
    }

    // Không `private`: `BypassWebView+Actions` (file khác) dùng chung các trạng thái này.
    @Environment(\.dismiss) var dismiss

    /// Chủ sở hữu duy nhất các tab (và mọi `WKWebView`) của phiên duyệt này.
    @StateObject var store = BypassBrowserTabStore()
    /// Chữ trong ô nhập địa chỉ — chỉ có nghĩa khi `isEditingUrl`; nhãn ô URL lúc thường suy từ tab.
    @State var inputUrl = ""
    @State var isEditingUrl = false
    @State var showingMenu = false
    @State var showingSourcePicker = false
    @State var showingAllHistorySheet = false
    @State var showingBrowserSettings = false
    /// Công tắc NSFW toàn app: tắt ⇒ Home không hiện ô của nguồn NSFW và ẩn lịch sử duyệt trang của chúng.
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) var includeNsfw = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BypassBrowserTabBar(store: store, onNewTab: { openNewTab() })
                BrowserLoadProgressLine(
                    isLoading: store.activeTab?.isLoading ?? false,
                    progress: store.activeTab?.progress ?? 0
                )
                if let tab = store.activeTab {
                    browserArea(for: tab, matches: importMatches(for: tab))
                } else {
                    Spacer()
                }
            }
            .pageTitle(store.activeTab?.displayTitle ?? "Trình duyệt")
            .toolbar {
                // Toàn màn, không vuốt đóng được ⇒ giữ "Xong". Nút mở ngăn kéo là ⋮ ở thanh dưới.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") {
                        dismiss()
                    }
                    .headerTextButton()
                }
            }
            .sideDrawerMenu(isPresented: $showingMenu, title: "Trình duyệt") {
                drawerContent
            }
            .onAppear {
                prepareInitialTab()
            }
            .onChange(of: store.activeTab?.urlString ?? "") { _, _ in
                // Trang đổi (hoặc đổi tab) trong lúc bảng chọn nguồn mở: nguồn khớp đã khác ⇒ đóng bảng.
                showingSourcePicker = false
            }
            .sheet(isPresented: $showingAllHistorySheet) {
                BrowserHistorySheetView(hidesNsfwHistory: !includeNsfw) { selectedUrl in
                    if let tab = store.activeTab, let target = URL(string: selectedUrl) {
                        tab.load(target)
                    }
                }
            }
            .sheet(isPresented: $showingBrowserSettings) {
                NavigationStack { BrowserSettingsView(showsDoneButton: true) }
                    .presentationDragIndicator(.visible)
            }
            // Sheet Dịch QT / Tra từ điển của menu nhấn giữ + bảng chia sẻ (`store.shareRequest`, cả mục "Chia sẻ" của
            // ngăn kéo lẫn menu link).
            .browserContextSheets(store: store)
        }
    }

    // MARK: - Vùng trang + thanh dưới

    /// Trang ở trên, thanh dưới gắn sát đáy ở dưới — trang kết thúc ngay trên thanh nên không có gì che nội dung. Bàn
    /// phím hiện (nhập địa chỉ / ô nhập của trang) ⇒ cả vùng co lên, thanh nằm ngay trên bàn phím.
    private func browserArea(for tab: BypassBrowserTab, matches: [ExtensionUrlMatcher.Match]) -> some View {
        VStack(spacing: 0) {
            Group {
                if Self.isHomeTab(tab) {
                    homePage(for: tab)
                } else {
                    BypassBrowserWebPane(webView: tab.webView)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                BrowserTranslateHintBanner(text: tab.translateHint)
                    .padding(.top, 12)
            }
            .overlay(alignment: .bottom) {
                BypassBrowserPopupBanner(store: store) // tự đệm đáy 10pt, tự ẩn sau ~5 s
            }

            BrowserBottomBar(
                store: store,
                tab: tab,
                isHome: Self.isHomeTab(tab),
                importMatches: showsImportButton(matches) ? matches : [],
                isImportPickerPresented: $showingSourcePicker,
                inputUrl: $inputUrl,
                isEditingUrl: $isEditingUrl,
                onBeginEditing: { beginEditingUrl(for: tab) },
                onSubmitUrl: { loadEnteredUrl(into: tab) },
                onReload: { reload(tab) },
                onOpenSettings: { showingBrowserSettings = true },
                onImport: { match in importBook(with: match) },
                onOpenMenu: { showingMenu = true }
            )
        }
    }

    private func homePage(for tab: BypassBrowserTab) -> some View {
        BypassBrowserHomeView(
            installedExtensions: RepositoryFilterPolicy.applyNsfwFilter(bookExtensions, includeNsfw: includeNsfw),
            hidesNsfwHistory: !includeNsfw,
            onSelectUrl: { url in
                if let target = URL(string: url) {
                    tab.load(target)
                }
            },
            onOpenAllHistory: {
                showingAllHistorySheet = true
            }
        )
    }

    /// Nút Import hiện khi màn có lối nhập, URL khớp tiện ích và không đang gõ địa chỉ.
    private func showsImportButton(_ matches: [ExtensionUrlMatcher.Match]) -> Bool {
        onImport != nil && !matches.isEmpty && !isEditingUrl
    }

    // MARK: - Ngăn kéo ⋮

    private var drawerContent: some View {
        let tab = store.activeTab
        let matches = tab.map { importMatches(for: $0) } ?? []
        let pageURL = tab.flatMap { webPageURL(of: $0) }
        return BrowserDrawerMenuContent(
            importSourceCount: matches.count,
            // Bảng chọn nguồn bật trên nút Import ⇒ chỉ cho bấm khi nút đang hiện (ẩn lúc nhập địa chỉ).
            canImport: showsImportButton(matches),
            isTranslating: tab?.isTranslating ?? false,
            hasWebPage: pageURL != nil,
            canOpenMoreTabs: store.canOpenMoreTabs,
            onImport: { importFromMenu(matches) },
            onSetTranslating: { isOn in
                if let active = store.activeTab, active.isTranslating != isOn {
                    store.toggleTranslation(for: active)
                }
            },
            onCopyLink: {
                if let pageURL { copyLink(pageURL) }
            },
            onShare: {
                if let pageURL { store.requestShare(url: pageURL) }
            },
            onNewTab: { openNewTab() },
            onGoHome: {
                if let active = store.activeTab { loadHome(into: active) }
            },
            onOpenHistory: { showingAllHistorySheet = true },
            onOpenSettings: { showingBrowserSettings = true }
        )
    }
}
