import Foundation
import UIKit
import WebKit

/// Một tab của trình duyệt bypass: sở hữu `WKWebView` riêng và phản chiếu trạng
/// thái hiển thị (tiêu đề, URL, tiến độ nạp, cờ điều hướng) qua KVO.
///
/// Tab nền vẫn tự cập nhật tiêu đề/URL vì observer thuộc chính tab, không thuộc
/// `UIViewRepresentable` — nhờ vậy đổi tab không mất trạng thái.
///
/// User-Agent, luật chặn quảng cáo và chế độ máy tính **không** gán ở đây: `BypassBrowserTabStore` áp qua
/// `WebContentConfigurator` (theo tên miền) ngay khi tạo tab và ở mỗi điều hướng khung chính. Dịch trang QT cũng do
/// store quyết (`BypassBrowserTabStore+Translation`); tab chỉ giữ trạng thái hiển thị của nó.
///
/// Mọi cờ `@Published` mới chỉ gán khi **khác** giá trị cũ: store chuyển tiếp `objectWillChange` của mọi tab lên chính
/// nó, gán lặp (vd mỗi khung hình cuộn) sẽ vẽ lại cả trình duyệt.
final class BypassBrowserTab: ObservableObject, Identifiable {
    /// Đổi hướng cuộn quá khoảng này mới lật `isScrolledDown`; trong khoảng này tính từ đầu trang luôn là `false`.
    private static let scrollFlipDistance: CGFloat = 24
    /// Thời gian dải báo tự dịch hiện trước khi tự ẩn.
    private static let translateHintDuration: TimeInterval = 2

    let id: String
    let webView: WKWebView

    @Published var title: String
    @Published var urlString: String
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0.0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    /// Tab **ẩn danh**: không ghi Lịch sử truy cập. `BypassBrowserTabStore` bật khi khung chính vào trang của nguồn tắt
    /// "Lưu lịch sử đọc/xem" (`BrowserSourceSiteIndex`); giữ tới khi về Home / mở tab mới, tab mở từ nó thừa hưởng.
    @Published var isIncognito: Bool = false
    /// Trang hiện tại đang hiển thị bản dịch QT. Chỉ store đổi (qua `setTranslating(_:)`): commit khung chính, nút dịch,
    /// đổi luật nhớ.
    @Published private(set) var isTranslating: Bool = false
    /// Chữ dải báo tự dịch ("Tự dịch QT · theo …"). Tự xoá sau 2 s; gán chữ mới trước hạn thì tính lại 2 s.
    @Published var translateHint: String? = nil {
        didSet { scheduleTranslateHintClear() }
    }
    /// Đang cuộn xuống (KVO `scrollView.contentOffset`): giao diện thu viên Import theo cờ này.
    @Published private(set) var isScrolledDown: Bool = false

    /// Bật/tắt dịch **bằng tay** (nút dịch trên thanh) cho `manualTranslateDomain` (tên miền chuẩn hoá lúc bấm). Không ghi
    /// nhớ: store xoá khi trang commit sang tên miền khác hoặc về Home. Chỉ `BypassBrowserTabStore+Translation` dùng.
    var manualTranslate: Bool?
    var manualTranslateDomain: String?
    /// Tên miền đã hiện dải báo tự dịch gần nhất: đọc liên tiếp nhiều chương cùng trang chỉ báo một lần, sang tên miền
    /// khác rồi quay lại mới báo lại. Chỉ `BypassBrowserTabStore+Translation` dùng.
    var autoTranslateHintDomain: String?

    /// Trạng thái luật/UA/chế độ hiển thị đã áp lên `webView` lần gần nhất (`nil` = chưa áp hoặc đã mất hiệu lực vì
    /// tab khác dùng chung `WKUserContentController` vừa đổi luật). Không `@Published`: View không vẽ theo nó.
    var appliedState: WebContentAppliedState?
    /// Rule list (định danh đối tượng) gắn ở lần áp gần nhất. Bộ lọc biên dịch xong muộn / bật-tắt / cập nhật làm bộ
    /// này lệch ⇒ điều hướng khung chính kế tiếp gắn lại (không huỷ + nạp lại), vì `appliedState` không đổi.
    var appliedRuleListIds: [ObjectIdentifier] = []
    /// Chống lặp cancel + nạp lại (R1): URL tab vừa tự nạp lại sau khi phải đổi luật/UA. Còn giá trị ⇒ chuỗi điều
    /// hướng hiện tại đã dùng lượt cancel duy nhất, mọi điều hướng khung chính tiếp theo (kể cả chuyển hướng của
    /// server) chỉ áp rồi cho qua. Xoá khi trang commit hoặc lỗi tải.
    var policyReloadURL: URL?

    /// URL cần nạp khi tab được hiển thị lần đầu. `nil` với tab do WebKit tự nạp
    /// (`window.open` / `target="_blank"`) — nạp lại tay sẽ làm hỏng navigation.
    private var pendingUrl: URL?
    private var observers: [NSKeyValueObservation] = []
    /// Token của lượt hẹn xoá `translateHint`: gán lại thì lượt cũ không xoá nhầm chữ mới.
    private var translateHintToken = 0
    /// Mốc cuộn: vị trí xa nhất theo hướng hiện tại, đo độ đổi hướng từ đây.
    private var scrollAnchorY: CGFloat = 0
    /// Tiêu đề đã dịch, nhớ theo tiêu đề gốc để `displayTitle` không dịch lại mỗi lần vẽ.
    private var translatedTitleCache: (source: String, translated: String)?

    init(
        id: String = UUID().uuidString,
        webView: WKWebView,
        initialUrl: URL? = nil,
        title: String = ""
    ) {
        self.id = id
        self.webView = webView
        self.title = title
        self.urlString = initialUrl?.absoluteString ?? ""
        self.pendingUrl = initialUrl
        webView.allowsBackForwardNavigationGestures = true
        attachObservers()
    }

    deinit {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
    }

    /// Tiêu đề rút gọn cho pill tab / header. Trang đang dịch QT và tiêu đề có chữ Hán ⇒ tiêu đề dịch
    /// (`TranslateUtils.translateMeta`, nhớ theo tiêu đề gốc).
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return isTranslating ? translatedTitle(trimmed) : trimmed }
        if let host = URL(string: urlString)?.host, !host.isEmpty { return host }
        return "Trang mới"
    }

    /// Chỉ `BypassBrowserTabStore` gọi; bỏ qua khi không đổi (xem doc của class).
    func setTranslating(_ value: Bool) {
        guard isTranslating != value else { return }
        isTranslating = value
    }

    private func translatedTitle(_ source: String) -> String {
        guard TranslateUtils.containsChinese(source) else { return source }
        if let cache = translatedTitleCache, cache.source == source { return cache.translated }
        let translated = TranslateUtils.translateMeta(source).trimmingCharacters(in: .whitespacesAndNewlines)
        let result = translated.isEmpty ? source : translated
        translatedTitleCache = (source, result)
        return result
    }

    private func scheduleTranslateHintClear() {
        translateHintToken &+= 1
        guard translateHint != nil else { return }
        let token = translateHintToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.translateHintDuration) { [weak self] in
            guard let self, self.translateHintToken == token, self.translateHint != nil else { return }
            self.translateHint = nil
        }
    }

    /// Lấy và xoá URL chờ nạp; gọi đúng một lần khi tab lên màn hình.
    func consumePendingUrl() -> URL? {
        let url = pendingUrl
        pendingUrl = nil
        return url
    }

    func load(_ url: URL) {
        pendingUrl = nil
        webView.load(URLRequest(url: url))
    }

    func stopLoadingAndDetach() {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    private func attachObservers() {
        let loadingObserver = webView.observe(\.isLoading, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async { self?.isLoading = webView.isLoading }
        }
        let progressObserver = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async { self?.progress = webView.estimatedProgress }
        }
        let titleObserver = webView.observe(\.title, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                if let webTitle = webView.title, !webTitle.isEmpty {
                    self?.title = webTitle
                }
            }
        }
        let urlObserver = webView.observe(\.url, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                if let webUrl = webView.url?.absoluteString {
                    self?.urlString = webUrl
                }
            }
        }
        let goBackObserver = webView.observe(\.canGoBack, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async { self?.canGoBack = webView.canGoBack }
        }
        let goForwardObserver = webView.observe(\.canGoForward, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async { self?.canGoForward = webView.canGoForward }
        }
        // Cuộn chạy trên main: xử lý tại chỗ (không `async` mỗi khung hình), lệch thread mới đẩy về main.
        let scrollObserver = webView.scrollView.observe(\.contentOffset, options: .new) { [weak self] scrollView, _ in
            if Thread.isMainThread {
                self?.trackScroll(scrollView)
            } else {
                DispatchQueue.main.async { self?.trackScroll(scrollView) }
            }
        }
        observers = [
            loadingObserver, progressObserver, titleObserver, urlObserver, goBackObserver, goForwardObserver, scrollObserver
        ]
    }

    /// Lật `isScrolledDown` khi đổi hướng quá `scrollFlipDistance` so với mốc; gần đầu trang ⇒ `false`. Vị trí được kẹp
    /// trong vùng cuộn thật để nảy ở cuối trang không bị tính là cuộn lên.
    private func trackScroll(_ scrollView: UIScrollView) {
        let inset = scrollView.adjustedContentInset
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + inset.top + inset.bottom)
        let y = min(max(scrollView.contentOffset.y + inset.top, 0), maxY)
        let flip = Self.scrollFlipDistance
        if y <= flip {
            scrollAnchorY = y
            if isScrolledDown { isScrolledDown = false }
            return
        }
        if isScrolledDown {
            if y > scrollAnchorY {
                scrollAnchorY = y
            } else if scrollAnchorY - y > flip {
                scrollAnchorY = y
                isScrolledDown = false
            }
        } else {
            if y < scrollAnchorY {
                scrollAnchorY = y
            } else if y - scrollAnchorY > flip {
                scrollAnchorY = y
                isScrolledDown = true
            }
        }
    }
}
