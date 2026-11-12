import Foundation
import UIKit
import WebKit

/// Thao tác của menu bôi đen và nhóm "Ảnh" trong trình duyệt người dùng (`BrowserWebView`, menu nhấn giữ link,
/// `BrowserImageMenuPresenter`). Toast nằm ở đây (tầng View) — `Sources/Services/**` không được gọi `ToastManager`.
///
/// Vùng chọn được lấy **lại** lúc bấm (`BrowserPageTranslator.selectionInfo(in:)`): `lastSelection` của webView chỉ là
/// bản xem trước. Trang đang dịch ⇒ Dịch QT / Tra từ điển / Sao chép bản dịch dùng **bản gốc** (`sourceText`); Tìm trên
/// web dùng chữ đang hiện (`text`). Không log nội dung trang hay URL.
///
/// Câu gốc của ba thao tác chữ Hán = chữ **đã chuyển** khi tab đang chuyển phồn → giản (1.3.846), kể cả khi không dịch
/// trang: bản gốc của đoạn đã dịch là chữ thô của trang nên chuyển lúc bấm (`pageSourceText`, `pageLookupRequest`).
extension BypassBrowserTabStore {
    /// Trần độ dài chuỗi gửi lên Google.
    private static let maxWebSearchLength = 500

    // MARK: - Menu bôi đen

    @MainActor
    func performSelectionAction(_ action: BrowserWebView.SelectionAction, in webView: BrowserWebView) {
        if case let .openLink(url) = action {
            openInNewTab(url, from: webView, activate: true)
            return
        }
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            await self.runSelectionAction(action, in: webView)
        }
    }

    @MainActor
    private func runSelectionAction(_ action: BrowserWebView.SelectionAction, in webView: BrowserWebView) async {
        switch action {
        case .translate:
            guard let info = await selectionOrToast(in: webView) else { return }
            contextActions.presentTranslate(source: await pageSourceText(info.sourceText, in: webView))
        case .lookup:
            guard let request = await BrowserContextMenuBridge.lookupRequest(in: webView) else {
                ToastManager.shared.show(message: "Không đọc được vùng chọn", type: .error)
                return
            }
            contextActions.presentLookup(await pageLookupRequest(request, in: webView))
        case .copyTranslation:
            guard let info = await selectionOrToast(in: webView) else { return }
            let source = await pageSourceText(info.sourceText, in: webView)
            let translated = await Task.detached(priority: .userInitiated) {
                // Câu gốc đã qua phồn → giản của trang (nếu có) ⇒ chỉ còn bước dịch, từ điển chung.
                ChineseTextPipeline.content(
                    source, ChineseTextPipeline.Options(converts: false, translates: true, dictionaryBookId: nil)
                )
            }.value
            let text = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            UIPasteboard.general.string = text.isEmpty ? source : translated
            ToastManager.shared.show(message: "Đã sao chép bản dịch", type: .success)
        case .searchWeb:
            guard let info = await selectionOrToast(in: webView),
                  let url = Self.webSearchURL(for: info.text) else { return }
            openInNewTab(url, from: webView, activate: true)
        case .openLink(let url):
            openInNewTab(url, from: webView, activate: true)
        }
    }

    @MainActor
    private func selectionOrToast(in webView: WKWebView) async -> BrowserSelectionInfo? {
        if let info = await BrowserPageTranslator.selectionInfo(in: webView) { return info }
        ToastManager.shared.show(message: "Không đọc được vùng chọn", type: .error)
        return nil
    }

    /// Câu gốc theo trang: tab đang chuyển phồn → giản ⇒ chữ đã chuyển (ngoài main — vùng chọn có thể dài).
    @MainActor
    private func pageSourceText(_ text: String, in webView: WKWebView) async -> String {
        guard tab(for: webView)?.isConvertingTraditional == true else { return text }
        return await Task.detached(priority: .userInitiated) {
            ChineseTextPipeline.convert(text, converts: true)
        }.value
    }

    /// Ngữ cảnh Tra từ điển theo trang: tab đang chuyển ⇒ chuyển cả đoạn lẫn từ. Độ dài UTF-16 của đoạn đổi ⇒ bỏ vị trí
    /// của từ (sheet tự tìm lần xuất hiện đầu tiên) — vị trí cũ có thể lệch.
    @MainActor
    private func pageLookupRequest(_ request: BrowserLookupRequest, in webView: WKWebView) async -> BrowserLookupRequest {
        guard tab(for: webView)?.isConvertingTraditional == true else { return request }
        return await Task.detached(priority: .userInitiated) {
            let context = ChineseTextPipeline.convert(request.context, converts: true)
            let word = ChineseTextPipeline.convert(request.word, converts: true)
            let keepsOffset = context.utf16.count == request.context.utf16.count
            return BrowserLookupRequest(context: context, word: word, wordOffset: keepsOffset ? request.wordOffset : nil)
        }.value
    }

    /// `https://www.google.com/search?q=…`; mã hoá cả `& + = ? # /` (bộ `urlQueryAllowed` để nguyên các ký tự này).
    static func webSearchURL(for text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        guard let query = String(trimmed.prefix(maxWebSearchLength)).addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        return URL(string: "https://www.google.com/search?q=" + query)
    }

    // MARK: - Mở link

    @MainActor
    func openInCurrentTab(_ url: URL, webView: WKWebView) {
        if let tab = tab(for: webView) {
            tab.load(url)
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    /// Tab mới thừa hưởng ẩn danh của tab mở nó (như `openBlockedPopup`). Đạt trần tab: mở ở tab trước mặt ⇒ nạp trên
    /// tab hiện tại; mở ở tab nền ⇒ báo, không nạp.
    @MainActor
    func openInNewTab(_ url: URL, from webView: WKWebView, activate: Bool) {
        let opener = tab(for: webView)
        if let tab = openTab(url: url, activate: activate) {
            tab.isIncognito = opener?.isIncognito ?? false
            // Không ai tiêu thụ `pendingUrl` của tab không phải tab đầu ⇒ tự nạp.
            tab.load(url)
            if !activate {
                ToastManager.shared.show(message: "Đã mở trong tab nền", type: .info)
            }
            return
        }
        guard activate else {
            ToastManager.shared.show(message: "Đã mở tối đa \(Self.maxTabCount) tab", type: .error)
            return
        }
        AppLogger.shared.log("[BypassBrowser] Đạt trần \(Self.maxTabCount) tab — mở link trên tab hiện tại")
        openInCurrentTab(url, webView: webView)
    }

    // MARK: - Ảnh

    @MainActor
    func performImageAction(_ action: BrowserWebView.ImageAction, imageURL: URL, in webView: WKWebView) {
        switch action {
        case .openInNewTab:
            openInNewTab(imageURL, from: webView, activate: true)
        case .save, .copy:
            Task { @MainActor [weak webView] in
                guard let webView else { return }
                let image: UIImage
                do {
                    image = try await Self.downloadImage(imageURL, for: webView)
                } catch {
                    AppLogger.shared.log("❌ [BrowserContextMenu] Không tải được ảnh: \(Self.logDescription(of: error))")
                    ToastManager.shared.show(message: "Không tải được ảnh", type: .error)
                    return
                }
                if action == .copy {
                    UIPasteboard.general.image = image
                    ToastManager.shared.show(message: "Đã sao chép ảnh", type: .success)
                } else if let error = await BrowserPhotoSaver.save(image) {
                    AppLogger.shared.log("❌ [BrowserContextMenu] Không lưu được ảnh: \(error.localizedDescription)")
                    ToastManager.shared.show(message: "Không lưu được ảnh — kiểm tra quyền Ảnh trong Cài đặt", type: .error)
                } else {
                    ToastManager.shared.show(message: "Đã lưu ảnh vào Ảnh", type: .success)
                }
            }
        }
    }

    /// Cookie kho WebKit + User-Agent + `Referer` (URL trang) lấy trên main, tải và giải mã ngoài main.
    @MainActor
    private static func downloadImage(_ url: URL, for webView: WKWebView) async throws -> UIImage {
        let referer = webView.url
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let userAgent = await BrowserContextMenuBridge.userAgent(of: webView)
        return try await BrowserImageFetcher.image(from: url, referer: referer, userAgent: userAgent, cookies: cookies)
    }

    /// Mô tả lỗi để log, **không** kèm URL (mô tả mặc định của `URLError` có URL ảnh).
    private static func logDescription(of error: Error) -> String {
        if let urlError = error as? URLError { return "URLError \(urlError.code.rawValue)" }
        if let fetchError = error as? BrowserImageFetcher.FetchError { return "\(fetchError)" }
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}
