import SwiftUI
import WebKit
import SwiftData

struct BypassWebView: View {
    let urlString: String
    let localPath: String?
    var onImport: ((_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Query private var allExtensions: [Extension]
    
    @State private var webView = WKWebView()
    @State private var isLoading = true
    @State private var progress: Double = 0.0
    @State private var title = "Trình duyệt"
    @State private var currentUrlString = ""
    
    private var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }
    
    var resolvedUrl: URL? {
        let resolvedString = JSExecutor.cleanAndResolveUrl(urlString, localPath: localPath)
        return URL(string: resolvedString)
    }
    
    var matchedExtensionInfo: (ext: Extension, regexp: String)? {
        findMatchingExtension(for: currentUrlString)
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if isLoading {
                        ProgressView(value: progress, total: 1.0)
                            .tint(.blue)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(height: 3)
                    } else {
                        Spacer().frame(height: 3)
                    }
                    
                    SwiftUIWebView(
                        webView: webView,
                        url: resolvedUrl,
                        isLoading: $isLoading,
                        progress: $progress,
                        title: $title,
                        currentUrlString: $currentUrlString
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
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        Button(action: {
                            webView.goBack()
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!webView.canGoBack)
                        
                        Button(action: {
                            webView.goForward()
                        }) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!webView.canGoForward)
                        
                        Button(action: {
                            webView.reload()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                if currentUrlString.isEmpty {
                    currentUrlString = resolvedUrl?.absoluteString ?? ""
                }
            }
        }
    }
    
    private func getExtensionRegexp(localPath: String) -> String? {
        guard !localPath.isEmpty else { return nil }
        let extUrl = URL(fileURLWithPath: localPath)
        let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: pluginJsonUrl.path),
              let data = try? Data(contentsOf: pluginJsonUrl),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = json["metadata"] as? [String: Any] else {
            return nil
        }
        return metadata["regexp"] as? String
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
    
    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        context.coordinator.setupObservers(for: webView)
        
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        
        if let url = url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SwiftUIWebView
        private var observers: [NSKeyValueObservation] = []
        
        init(_ parent: SwiftUIWebView) {
            self.parent = parent
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
            
            self.observers = [loadingObserver, progressObserver, titleObserver, urlObserver]
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
