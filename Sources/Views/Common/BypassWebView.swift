import SwiftUI
import WebKit
import SwiftData

struct BypassWebView: View {
    private struct ExtensionMatch: Identifiable {
        let ext: Extension
        let regexp: String

        var id: String { ext.packageId }
    }

    let urlString: String
    let host: String?
    var onImport: ((_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void)? = nil

    init(urlString: String, host: String? = nil, onImport: ((_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void)? = nil) {
        self.urlString = urlString
        self.host = host
        self.onImport = onImport
    }

    @Environment(\.dismiss) private var dismiss
    @Query private var allExtensions: [Extension]

    /// Chủ sở hữu duy nhất các tab (và mọi `WKWebView`) của phiên duyệt này.
    @StateObject private var store = BypassBrowserTabStore()
    @State private var inputUrl = ""
    @State private var isEditingUrl = false
    @State private var showingSourcePicker = false

    private var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }

    private var bookExtensions: [Extension] {
        activeExtensions.filter { !$0.sourceUrl.isEmpty }
    }

    var resolvedUrl: URL? {
        if urlString == "home" { return nil }
        let resolvedString = JSExecutor.cleanAndResolveUrl(urlString, host: host)
        return URL(string: resolvedString)
    }

    private var currentUrlString: String {
        store.activeTab?.urlString ?? ""
    }

    private var matchingExtensionInfos: [ExtensionMatch] {
        findMatchingExtensions(for: currentUrlString)
    }

    private var canImportCurrentPage: Bool {
        onImport != nil && !matchingExtensionInfos.isEmpty
    }

    private var navigationTitleText: String {
        guard let tab = store.activeTab else { return "Trình duyệt" }
        if store.tabs.count > 1 {
            return "\(tab.displayTitle) (\(store.tabs.count) tab)"
        }
        return tab.displayTitle
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if store.tabs.count > 1 {
                    BypassBrowserTabBar(store: store)
                    Divider()
                }

                if let tab = store.activeTab {
                    BypassBrowserWebPane(webView: tab.webView)

                    if tab.isLoading {
                        ProgressView(value: tab.progress, total: 1.0)
                            .tint(.blue)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(height: 3)
                    } else {
                        Divider()
                    }

                    addressBar(for: tab)
                } else {
                    Spacer()
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        openNewTab()
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .disabled(!store.canOpenMoreTabs)
                    .accessibilityLabel("Tab mới")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .confirmationDialog("Chọn nguồn import", isPresented: $showingSourcePicker, titleVisibility: .visible) {
                ForEach(matchingExtensionInfos) { match in
                    Button(match.ext.name) {
                        importBook(with: match)
                    }
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text(currentUrlString)
            }
            .onAppear {
                prepareInitialTab()
            }
            .onChange(of: currentUrlString) { _, newValue in
                syncInputUrl(with: newValue)
            }
            .onChange(of: store.activeTabId) { _, _ in
                syncInputUrl(with: currentUrlString)
            }
        }
    }

    /// Thanh địa chỉ URL, điều hướng và import truyện.
    @ViewBuilder
    private func addressBar(for tab: BypassBrowserTab) -> some View {
        HStack(spacing: 8) {
            Button {
                tab.webView.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(tab.canGoBack ? .blue : .gray)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(!tab.canGoBack)

            Button {
                tab.webView.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(tab.canGoForward ? .blue : .gray)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(!tab.canGoForward)

            Button {
                loadHome(into: tab)
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.blue)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }

            urlField(for: tab)

            Button {
                if isShowingReloadIcon(for: tab) {
                    if tab.urlString == "about:blank" {
                        loadHome(into: tab)
                    } else {
                        tab.webView.reload()
                    }
                } else {
                    loadEnteredUrl(into: tab)
                }
            } label: {
                Image(systemName: isShowingReloadIcon(for: tab) ? "arrow.clockwise" : "arrow.right.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 36)
            }

            Button {
                handleImportTap()
            } label: {
                Label("Import truyện", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .labelStyle(.iconOnly)
                    .foregroundColor(canImportCurrentPage ? .blue : .gray)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(!canImportCurrentPage)
            .accessibilityLabel("Import truyện")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func urlField(for tab: BypassBrowserTab) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundColor(.secondary)

            URLBarTextField(
                placeholder: "Nhập địa chỉ web...",
                text: $inputUrl,
                isEditing: $isEditingUrl,
                onSubmit: { loadEnteredUrl(into: tab) }
            )
            .frame(maxWidth: .infinity)

            if !inputUrl.isEmpty {
                Button {
                    inputUrl = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func isShowingReloadIcon(for tab: BypassBrowserTab) -> Bool {
        inputUrl == tab.urlString || tab.urlString == "about:blank"
    }

    // MARK: - Tab lifecycle

    private func prepareInitialTab() {
        let isFirstMount = store.tabs.isEmpty
        let tab = store.prepareFirstTab(url: resolvedUrl)
        guard isFirstMount else { return }

        if let pending = tab.consumePendingUrl() {
            tab.load(pending)
            inputUrl = pending.absoluteString
        } else {
            loadHome(into: tab)
        }
    }

    private func openNewTab() {
        guard let tab = store.openTab() else { return }
        loadHome(into: tab)
    }

    private func loadHome(into tab: BypassBrowserTab) {
        let html = BypassBrowserHomePage.html(for: bookExtensions)
        tab.webView.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        tab.title = "Home"
        tab.urlString = "about:blank"
        inputUrl = "Home"
    }

    private func loadEnteredUrl(into tab: BypassBrowserTab) {
        var cleanUrl = inputUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty, cleanUrl != "Home" else { return }

        if !cleanUrl.lowercased().hasPrefix("http://") && !cleanUrl.lowercased().hasPrefix("https://") {
            cleanUrl = "https://" + cleanUrl
        }

        guard let url = URL(string: cleanUrl) else { return }
        tab.load(url)
    }

    /// Đồng bộ URL hiển thị; bỏ qua khi người dùng đang gõ để không ghi đè.
    private func syncInputUrl(with newValue: String) {
        guard !isEditingUrl else { return }
        if newValue.isEmpty || newValue == "about:blank" {
            inputUrl = "Home"
        } else {
            inputUrl = newValue
        }
    }
    // MARK: - Import truyện

    private func handleImportTap() {
        let matches = matchingExtensionInfos
        guard !matches.isEmpty else { return }

        if matches.count == 1, let match = matches.first {
            importBook(with: match)
        } else {
            showingSourcePicker = true
        }
    }

    private func importBook(with match: ExtensionMatch) {
        onImport?(currentUrlString, match.ext.packageId, match.ext.name)
        dismiss()
    }

    private static var regexpCache: [String: String] = [:]

    private func getExtensionRegexp(localPath: String) -> String? {
        guard !localPath.isEmpty else { return nil }
        if let cached = Self.regexpCache[localPath] {
            return cached
        }
        let extUrl = URL(fileURLWithPath: localPath)
        let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: pluginJsonUrl.path),
              let data = try? Data(contentsOf: pluginJsonUrl),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = json["metadata"] as? [String: Any] else {
            return nil
        }
        let regexp = metadata["regexp"] as? String
        if let regexp = regexp {
            Self.regexpCache[localPath] = regexp
        }
        return regexp
    }

    private func findMatchingExtensions(for urlString: String) -> [ExtensionMatch] {
        guard !urlString.isEmpty, urlString.lowercased().hasPrefix("http") else { return [] }

        var matches: [ExtensionMatch] = []
        for ext in activeExtensions {
            guard let regexpStr = getExtensionRegexp(localPath: ext.localPath), !regexpStr.isEmpty else {
                continue
            }

            if let regex = try? NSRegularExpression(pattern: regexpStr, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: urlString.utf16.count)
                if regex.firstMatch(in: urlString, options: [], range: range) != nil {
                    matches.append(ExtensionMatch(ext: ext, regexp: regexpStr))
                }
            }
        }
        return matches
    }
}
