import SwiftUI
import WebKit
import SwiftData

struct BypassWebView: View {
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
    
    @StateObject private var webViewStore = WebViewStore()
    private var webView: WKWebView { webViewStore.webView }
    @State private var isLoading = true
    @State private var progress: Double = 0.0
    @State private var title = "Trình duyệt"
    @State private var currentUrlString = ""
    @State private var inputUrl = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    
    private var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }
    
    var resolvedUrl: URL? {
        if urlString == "home" { return nil }
        let resolvedString = JSExecutor.cleanAndResolveUrl(urlString, host: host)
        return URL(string: resolvedString)
    }
    
    var matchedExtensionInfo: (ext: Extension, regexp: String)? {
        findMatchingExtension(for: currentUrlString)
    }
    
    private var bookExtensions: [Extension] {
        activeExtensions.filter { !$0.sourceUrl.isEmpty }
    }
    
    private func generateHomeHtml() -> String {
        let bookExts = bookExtensions
        var extsHtml = ""
        
        let fallbackIconBase64 = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiMwMDdhZmYiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMjEgMTZWOGEyIDIgMCAwIDAtMS0xLjczbC03LTRhMiAyIDAgMCAwLTIgMGwtNyA0QTIgMiAwIDAgMCAzIDh2OGEyIDIgMCAwIDAgMSAxLjczbDcgNGEyIDIgMCAwIDAgMiAwbDctNGEyIDIgMCAwIDAgMS0xLzczeiI+PC9wYXRoPjwvc3ZnPg=="
        
        for ext in bookExts {
            var iconSrc = fallbackIconBase64
            if !ext.localPath.isEmpty {
                let iconPath = URL(fileURLWithPath: ext.localPath).appendingPathComponent("icon.png").path
                if FileManager.default.fileExists(atPath: iconPath),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: iconPath)) {
                    let base64 = data.base64EncodedString()
                    iconSrc = "data:image/png;base64,\(base64)"
                } else if let iconUrl = ext.iconUrl, !iconUrl.isEmpty {
                    iconSrc = iconUrl
                }
            } else if let iconUrl = ext.iconUrl, !iconUrl.isEmpty {
                iconSrc = iconUrl
            }
            
            extsHtml += """
            <a class="card" href="\(ext.sourceUrl)">
                <div class="ext-header">
                    <img class="ext-icon" src="\(iconSrc)" onerror="this.onerror=null; this.src='\(fallbackIconBase64)';"/>
                    <div class="ext-name">\(ext.name)</div>
                </div>
                <div class="ext-url">\(ext.sourceUrl)</div>
            </a>
            """
        }
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <title>Home</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: #f2f2f7;
                    color: #1c1c1e;
                    margin: 0;
                    padding: 20px;
                }
                h1 {
                    font-size: 24px;
                    font-weight: 700;
                    margin-bottom: 20px;
                    text-align: center;
                }
                .section-title {
                    font-size: 14px;
                    font-weight: 600;
                    text-transform: uppercase;
                    color: #8e8e93;
                    margin-top: 24px;
                    margin-bottom: 10px;
                    padding-left: 5px;
                }
                .grid {
                    display: grid;
                    grid-template-columns: repeat(2, 1fr);
                    gap: 12px;
                }
                .card {
                    background-color: #ffffff;
                    border-radius: 12px;
                    padding: 16px;
                    text-decoration: none;
                    color: inherit;
                    display: flex;
                    flex-direction: column;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
                }
                .card:active {
                    background-color: #e5e5ea;
                }
                .card-title {
                    font-size: 17px;
                    font-weight: 600;
                    color: #007aff;
                    margin-bottom: 4px;
                }
                .card-subtitle {
                    font-size: 13px;
                    color: #8e8e93;
                    word-break: break-all;
                }
                .ext-header {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    margin-bottom: 6px;
                }
                .ext-icon {
                    width: 24px;
                    height: 24px;
                    border-radius: 5px;
                    object-fit: cover;
                    flex-shrink: 0;
                }
                .ext-name {
                    font-size: 16px;
                    font-weight: 600;
                    color: #1c1c1e;
                    white-space: nowrap;
                    overflow: hidden;
                    text-overflow: ellipsis;
                }
                .ext-url {
                    font-size: 12px;
                    color: #8e8e93;
                    word-break: break-all;
                }
                .list {
                    display: flex;
                    flex-direction: column;
                    gap: 10px;
                    margin-top: 10px;
                }
                .list .card {
                    flex-direction: column;
                    justify-content: center;
                }
            </style>
        </head>
        <body>
            <h1>Home</h1>
            
            <div class="section-title">Công cụ Tìm kiếm</div>
            <div class="grid">
                <a class="card" href="https://www.google.com">
                    <div class="card-title">Google</div>
                    <div class="card-subtitle">google.com</div>
                </a>
                <a class="card" href="https://www.bing.com">
                    <div class="card-title">Bing</div>
                    <div class="card-subtitle">bing.com</div>
                </a>
                <a class="card" href="https://www.baidu.com">
                    <div class="card-title">Baidu</div>
                    <div class="card-subtitle">baidu.com</div>
                </a>
            </div>
            
            <div class="section-title">Tiện ích đã cài đặt</div>
            <div class="list">
                \(extsHtml.isEmpty ? "<div style='padding: 16px; text-align: center; color: #8e8e93; font-size: 15px; background: white; border-radius: 12px;'>Chưa có nguồn truyện nào được cài đặt</div>" : extsHtml)
            </div>
        </body>
        </html>
        """
        return html
    }
    
    private func loadHomeHtml() {
        let html = generateHomeHtml()
        webView.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        currentUrlString = "about:blank"
        inputUrl = "Home"
        title = "Home"
    }
    
    private func loadEnteredUrl() {
        var cleanUrl = inputUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty else { return }
        
        if !cleanUrl.lowercased().hasPrefix("http://") && !cleanUrl.lowercased().hasPrefix("https://") {
            cleanUrl = "https://" + cleanUrl
        }
        
        if let url = URL(string: cleanUrl) {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Thanh địa chỉ URL & Điều hướng
                    HStack(spacing: 8) {
                        // Nút Quay lại (Back/Previous)
                        Button(action: {
                            webView.goBack()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(canGoBack ? .blue : .gray)
                                .frame(width: 36, height: 36)
                                .background(Color(.systemGray6))
                                .clipShape(Circle())
                        }
                        .disabled(!canGoBack)
                        
                        // Nút Tiếp tục (Forward)
                        Button(action: {
                            webView.goForward()
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(canGoForward ? .blue : .gray)
                                .frame(width: 36, height: 36)
                                .background(Color(.systemGray6))
                                .clipShape(Circle())
                        }
                        .disabled(!canGoForward)
                        
                        // Nút Home
                        Button(action: {
                            loadHomeHtml()
                        }) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.blue)
                                .frame(width: 36, height: 36)
                                .background(Color(.systemGray6))
                                .clipShape(Circle())
                        }
                        
                        // Ô nhập URL
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("Nhập địa chỉ web...", text: $inputUrl, onCommit: {
                                loadEnteredUrl()
                            })
                            .font(.system(size: 15))
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            
                            if !inputUrl.isEmpty {
                                Button(action: {
                                    inputUrl = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        // Nút Reload / Go
                        Button(action: {
                            if inputUrl == currentUrlString || currentUrlString == "about:blank" {
                                if currentUrlString == "about:blank" {
                                    loadHomeHtml()
                                } else {
                                    webView.reload()
                                }
                            } else {
                                loadEnteredUrl()
                            }
                        }) {
                            Image(systemName: (inputUrl == currentUrlString || currentUrlString == "about:blank") ? "arrow.clockwise" : "arrow.right.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    
                    if isLoading {
                        ProgressView(value: progress, total: 1.0)
                            .tint(.blue)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(height: 3)
                    } else {
                        Divider()
                    }
                    
                    SwiftUIWebView(
                        webView: webView,
                        url: resolvedUrl,
                        isLoading: $isLoading,
                        progress: $progress,
                        title: $title,
                        currentUrlString: $currentUrlString,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward
                    )
                }
                
                // Banner Import nổi ở đáy nếu khớp regex
                if let info = matchedExtensionInfo {
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Phát hiện link truyện hợp lệ!")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(info.ext.name)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                onImport?(currentUrlString, info.ext.packageId, info.ext.name)
                                dismiss()
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.blue)
                                    .background(Color.white.clipShape(Circle()))
                                    .shadow(radius: 1)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground).opacity(0.95))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: -2)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: currentUrlString)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                if urlString == "home" {
                    loadHomeHtml()
                } else {
                    currentUrlString = resolvedUrl?.absoluteString ?? ""
                    inputUrl = currentUrlString
                }
            }
            .onChange(of: currentUrlString) { _, newValue in
                if newValue == "about:blank" || newValue.isEmpty {
                    inputUrl = "Home"
                    title = "Home"
                } else {
                    inputUrl = newValue
                }
            }
        }
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
    
    private func findMatchingExtension(for urlString: String) -> (ext: Extension, regexp: String)? {
        guard !urlString.isEmpty, urlString.lowercased().hasPrefix("http") else { return nil }
        
        for ext in activeExtensions {
            guard let regexpStr = getExtensionRegexp(localPath: ext.localPath), !regexpStr.isEmpty else {
                continue
            }
            
            if let regex = try? NSRegularExpression(pattern: regexpStr, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: urlString.utf16.count)
                if regex.firstMatch(in: urlString, options: [], range: range) != nil {
                    return (ext, regexpStr)
                }
            }
        }
        return nil
    }
}

struct SwiftUIWebView: UIViewRepresentable {
    let webView: WKWebView
    let url: URL?
    @Binding var isLoading: Bool
    @Binding var progress: Double
    @Binding var title: String
    @Binding var currentUrlString: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        context.coordinator.setupObservers(for: webView)
        
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        
        context.coordinator.loadIfNeeded(url, in: webView)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // SwiftUI may preserve the representable/coordinator between two
        // presentations. Refresh bindings and explicitly load a changed target
        // instead of leaving the previous page (or a blank page) in place.
        context.coordinator.parent = self
        context.coordinator.loadIfNeeded(url, in: uiView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SwiftUIWebView
        private var observers: [NSKeyValueObservation] = []
        private var lastRequestedURL: URL?
        
        init(_ parent: SwiftUIWebView) {
            self.parent = parent
        }

        func loadIfNeeded(_ url: URL?, in webView: WKWebView) {
            guard let url, url != lastRequestedURL else { return }
            lastRequestedURL = url
            webView.load(URLRequest(url: url))
        }
        
        func setupObservers(for webView: WKWebView) {
            let loadingObserver = webView.observe(\.isLoading, options: .new) { [weak self] webView, change in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.parent.isLoading = webView.isLoading
                }
            }
            
            let progressObserver = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, change in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.parent.progress = webView.estimatedProgress
                }
            }
            
            let titleObserver = webView.observe(\.title, options: .new) { [weak self] webView, change in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let webTitle = webView.title, !webTitle.isEmpty {
                        self.parent.title = webTitle
                    }
                }
            }
            
            let urlObserver = webView.observe(\.url, options: .new) { [weak self] webView, change in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let webUrl = webView.url?.absoluteString {
                        self.parent.currentUrlString = webUrl
                    }
                }
            }
            
            let canGoBackObserver = webView.observe(\.canGoBack, options: .new) { [weak self] webView, change in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.parent.canGoBack = webView.canGoBack
                }
            }
            
            let canGoForwardObserver = webView.observe(\.canGoForward, options: .new) { [weak self] webView, change in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.parent.canGoForward = webView.canGoForward
                }
            }
            
            self.observers = [loadingObserver, progressObserver, titleObserver, urlObserver, canGoBackObserver, canGoForwardObserver]
        }
        
        deinit {
            observers.forEach { $0.invalidate() }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let urlString = url.absoluteString
                if isDomainBlocked(urlString) {
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}

fileprivate func isDomainBlocked(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
        return false
    }
    let blockedDomains = [
        "google-analytics.com",
        "doubleclick.net",
        "googlesyndication.com",
        "mgid.com",
        "taboola.com",
        "erodalabs.com",
        "tip-top.one",
        "bet88", "w88", "fun88", "shopee.vn", "lazada.vn"
    ]
    for blocked in blockedDomains {
        if host.contains(blocked) {
            return true
        }
    }
    return false
}

class WebViewStore: ObservableObject {
    let webView = WKWebView()
}
