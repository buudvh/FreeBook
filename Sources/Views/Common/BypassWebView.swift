import SwiftUI
import WebKit

/// Trình duyệt người dùng (mockup 2026-10-30 "Trình duyệt mới"):
/// - Header gọn: `.pageTitle(tiêu đề trang)` (đã dịch khi trang đang dịch QT), nút "…" mở ngăn kéo, "Xong" ngoài cùng.
/// - Dải tab viên thuốc luôn hiện (`BypassBrowserTabBar`) + vạch tiến độ 2pt (`BrowserLoadProgressLine`).
/// - Trang (web hoặc Home) chiếm hết phần còn lại, **kéo xuống tận mép màn**; dải báo tự dịch nổi phía trên.
/// - Cụm nổi phía dưới, đè lên trang: dải báo popup bị chặn, viên Import (`BrowserImportPill`), thanh kính
///   (`BrowserBottomBar`: lùi, tiến, ô URL, nút dịch).
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
    /// Safe area đáy (vạch Home) của vùng trang khi **không** có bàn phím; bàn phím đang hiện ⇒ 0. Đo bằng
    /// `GeometryReader` nền bỏ qua safe area `.container` (vẫn tôn trọng bàn phím).
    @State private var bottomSafeInset: CGFloat = 0
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
                // Toàn màn, không vuốt đóng được ⇒ giữ "Xong", ngoài cùng bên phải; "…" đứng ngay trước.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingMenu = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 38)
                    }
                    .accessibilityLabel("Tuỳ chọn trình duyệt")
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

    // MARK: - Vùng trang + cụm nổi

    /// Trang kéo xuống tận mép màn; thanh nổi đặt theo safe area đáy rồi hạ vào vùng vạch Home như mockup. Bàn phím
    /// hiện (nhập địa chỉ / ô nhập của trang) ⇒ cả vùng co lên trên bàn phím, thanh nằm ngay trên bàn phím.
    private func browserArea(for tab: BypassBrowserTab, matches: [ExtensionUrlMatcher.Match]) -> some View {
        ZStack(alignment: .bottom) {
            if Self.isHomeTab(tab) {
                homePage(for: tab)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear
                            .frame(height: chromeClearance)
                            .allowsHitTesting(false)
                    }
            } else {
                // Viên Import (kể cả khi thu còn icon) cũng che góc phải dòng cuối ⇒ chừa thêm chỗ khi viên hiện.
                BypassBrowserWebPane(
                    webView: tab.webView,
                    bottomObstruction: bottomSafeInset + chromeClearance
                        + (showsImportPill(matches) ? Self.importPillClearance : 0)
                )
                .ignoresSafeArea(.container, edges: .bottom)
            }

            bottomChrome(for: tab, matches: matches)
        }
        .overlay(alignment: .top) {
            BrowserTranslateHintBanner(text: tab.translateHint)
                .padding(.top, 12)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { bottomSafeInset = proxy.safeAreaInsets.bottom }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, value in
                        bottomSafeInset = value
                    }
            }
            .ignoresSafeArea(.container, edges: .bottom)
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

    private func bottomChrome(for tab: BypassBrowserTab, matches: [ExtensionUrlMatcher.Match]) -> some View {
        VStack(spacing: 0) {
            BypassBrowserPopupBanner(store: store) // dải báo cửa sổ bật lên bị chặn, tự đệm đáy 10pt

            if showsImportPill(matches) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    BrowserImportPill(
                        matches: matches,
                        isCollapsed: tab.isScrolledDown,
                        isPickerPresented: $showingSourcePicker,
                        onImport: { match in importBook(with: match) }
                    )
                }
                .padding(.trailing, 12)
                .padding(.bottom, 10)
            }

            BrowserBottomBar(
                store: store,
                tab: tab,
                isHome: Self.isHomeTab(tab),
                inputUrl: $inputUrl,
                isEditingUrl: $isEditingUrl,
                onBeginEditing: { beginEditingUrl(for: tab) },
                onSubmitUrl: { loadEnteredUrl(into: tab) },
                onReload: { reload(tab) },
                onOpenSettings: { showingBrowserSettings = true }
            )
            .padding(.horizontal, 10)
        }
        .padding(.bottom, barBottomPadding)
    }

    /// Đệm đáy của thanh so với mép dưới safe area. Có vạch Home ⇒ hạ thanh vào vùng vạch (mockup: đáy thanh cách mép
    /// màn 22pt khi vạch Home cao 34pt), chừa ≥ 10pt trên mép màn. Không có (máy nút Home, hoặc bàn phím đang hiện) ⇒ 8pt.
    private var barBottomPadding: CGFloat {
        bottomSafeInset > 0 ? -min(12, max(0, bottomSafeInset - 10)) : 8
    }

    /// Viên Import hiện khi màn có lối nhập, URL khớp tiện ích và không đang gõ địa chỉ.
    private func showsImportPill(_ matches: [ExtensionUrlMatcher.Match]) -> Bool {
        onImport != nil && !matches.isEmpty && !isEditingUrl
    }

    /// Chiều cao viên Import (42) + khoảng cách tới thanh (10).
    private static let importPillClearance: CGFloat = 52

    /// Khoảng trang phải chừa phía trên safe area đáy để nội dung cuối không bị thanh che (thêm 8pt cho thoáng).
    private var chromeClearance: CGFloat {
        barBottomPadding + BrowserBottomBar.height + 8
    }

    // MARK: - Ngăn kéo "…"

    private var drawerContent: some View {
        let tab = store.activeTab
        let matches = tab.map { importMatches(for: $0) } ?? []
        let pageURL = tab.flatMap { webPageURL(of: $0) }
        return BrowserDrawerMenuContent(
            importSourceCount: matches.count,
            // Bảng chọn nguồn bật trên viên Import ⇒ chỉ cho bấm khi viên đang hiện (ẩn lúc nhập địa chỉ).
            canImport: onImport != nil && !matches.isEmpty && !isEditingUrl,
            hasWebPage: pageURL != nil,
            canOpenMoreTabs: store.canOpenMoreTabs,
            onImport: { importFromMenu(matches) },
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
