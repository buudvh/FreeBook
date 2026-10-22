import Foundation
import WebKit

/// Chờ trang "lắng" sau lần tải xong đầu tiên của `LegadoWebViewFetcher` (spec §4.4).
///
/// `WebViewLoader.completion` chỉ báo **lần đầu** khung chính tải xong (hoặc lỗi — khi đó HTML rỗng). Trang thử thách
/// chống bot bằng JS (vd. qidian: HTTP 202, `<body>` rỗng + `probe.js`) tải xong lần đó rồi mới chạy JS lấy dấu vân tay,
/// đặt cookie và `location.reload()`: lấy HTML ngay lúc ấy là lấy nhầm trang thử thách, dọn WebView ngay thì JS cũng không
/// kịp đặt cookie. Vì vậy sau tín hiệu đầu, dò `webView.isLoading` mỗi `settlePollInterval` trên main:
/// - đang tải (điều hướng mới) ⇒ chờ tiếp; phải yên liên tục `settleQuietWindow` mới xét DOM;
/// - DOM trông như trang chờ (gần như không chữ, ít ảnh, có script hoặc meta refresh) ⇒ chờ tiếp, tối đa
///   `interstitialWait` kể từ lần trang tải xong gần nhất (điều hướng mới làm lại đồng hồ);
/// - trần cứng `deadline` (≤ lúc nạp + timeout của request): quá hạn thì lấy DOM hiện có.
extension LegadoWebViewFetcher {
    /// Tiến trình chờ của một lượt tải; chỉ đọc/ghi trên main.
    private struct SettleProgress {
        /// Lúc trang thôi tải gần nhất; `nil` khi đang có điều hướng.
        var quietSince: Date?
        /// Lúc trang tải xong gần nhất: hạn chờ trang thử thách tính từ đây.
        var loadedAt: Date
        /// Đã thấy một điều hướng mới sau tín hiệu đầu.
        var sawLoad = false
        /// Lần tải đầu báo lỗi (`WebViewLoader` trả chuỗi rỗng).
        let firstFailed: Bool
        let firstHTML: String
    }

    private static let settlePollInterval: TimeInterval = 0.25
    /// Trang thường chỉ tốn thêm khoảng này (cộng hai lần đọc DOM).
    private static let settleQuietWindow: TimeInterval = 0.5
    private static let interstitialWait: TimeInterval = 8
    private static let interstitialMaxText = 64
    private static let interstitialMaxImages = 3

    /// `[số ký tự chữ thấy được (dừng đếm ở ngưỡng), số ảnh, số script, có meta refresh]`; lỗi ⇒ `null`.
    /// `createTreeWalker(body, 4)` = chỉ nút chữ; bỏ chữ trong script/style.
    private static let settleProbeScript = """
    (function(){try{var d=document,b=d.body,n=0;if(b){var w=d.createTreeWalker(b,4,null),x;\
    while(n<\(interstitialMaxText)&&(x=w.nextNode())){var p=x.parentNode?x.parentNode.nodeName:'';\
    if(p!=='SCRIPT'&&p!=='STYLE'&&p!=='NOSCRIPT'&&p!=='TEMPLATE')n+=x.nodeValue.trim().length;}}\
    return [n,d.images.length,d.scripts.length,d.querySelector('meta[http-equiv="refresh" i]')?1:0];\
    }catch(e){return null;}})()
    """

    /// Gọi trên main khi `WebViewLoader` báo lần tải đầu kết thúc (`firstHTML` = HTML lúc đó, rỗng nếu lỗi).
    /// `done` chạy tối đa một lần, trên main, với HTML cuối; không chạy nếu `isFinished()` đã `true` (huỷ/hết giờ).
    static func settle(_ loader: WebViewLoader, firstHTML: String, deadline: Date,
                       isFinished: @escaping () -> Bool, done: @escaping (String) -> Void) {
        let progress = SettleProgress(quietSince: nil, loadedAt: Date(), firstFailed: firstHTML.isEmpty,
                                      firstHTML: firstHTML)
        settleTick(loader, progress: progress, deadline: deadline, isFinished: isFinished, done: done)
    }

    private static func settleTick(_ loader: WebViewLoader, progress: SettleProgress, deadline: Date,
                                   isFinished: @escaping () -> Bool, done: @escaping (String) -> Void) {
        guard !isFinished() else { return }
        var next = progress
        let now = Date()
        let loading = MainActor.assumeIsolated { loader.webView.isLoading }
        if loading {
            next.sawLoad = true
            next.quietSince = nil
        } else if next.quietSince == nil {
            next.quietSince = now
            next.loadedAt = now
        }
        let pastDeadline = now >= deadline
        let quietEnough = next.quietSince.map { now.timeIntervalSince($0) >= settleQuietWindow } ?? false
        guard pastDeadline || quietEnough else {
            scheduleSettleTick(loader, progress: next, deadline: deadline, isFinished: isFinished, done: done)
            return
        }
        if next.firstFailed && !next.sawLoad {
            // Lần tải đầu lỗi và không có điều hướng nào tiếp theo: giữ hành vi cũ (thân rỗng).
            done("")
            return
        }
        let snapshot = next
        MainActor.assumeIsolated {
            loader.webView.evaluateJavaScript(settleProbeScript) { value, _ in
                guard !isFinished() else { return }
                let waitedEnough = Date().timeIntervalSince(snapshot.loadedAt) >= interstitialWait
                if !pastDeadline, !waitedEnough, looksInterstitial(value) {
                    scheduleSettleTick(loader, progress: snapshot, deadline: deadline, isFinished: isFinished, done: done)
                    return
                }
                readOuterHTML(loader, fallback: snapshot.firstHTML, isFinished: isFinished, done: done)
            }
        }
    }

    private static func scheduleSettleTick(_ loader: WebViewLoader, progress: SettleProgress, deadline: Date,
                                           isFinished: @escaping () -> Bool, done: @escaping (String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + settlePollInterval) { [weak loader] in
            guard let loader else { return }
            settleTick(loader, progress: progress, deadline: deadline, isFinished: isFinished, done: done)
        }
    }

    private static func readOuterHTML(_ loader: WebViewLoader, fallback: String,
                                      isFinished: @escaping () -> Bool, done: @escaping (String) -> Void) {
        MainActor.assumeIsolated {
            loader.webView.evaluateJavaScript("document.documentElement.outerHTML") { value, _ in
                guard !isFinished() else { return }
                done(value as? String ?? fallback)
            }
        }
    }

    /// Trang chờ/thử thách: gần như không có chữ, ít ảnh, nhưng có script hoặc meta refresh (sẽ tự điều hướng tiếp).
    /// Kết quả dò không đọc được ⇒ coi như trang đã lắng.
    private static func looksInterstitial(_ probe: Any?) -> Bool {
        guard let values = probe as? [Any], values.count >= 4 else { return false }
        let numbers = values.map { ($0 as? NSNumber)?.intValue ?? 0 }
        let text = numbers[0], images = numbers[1], scripts = numbers[2], refresh = numbers[3]
        return text < interstitialMaxText && images < interstitialMaxImages && (scripts > 0 || refresh > 0)
    }
}
