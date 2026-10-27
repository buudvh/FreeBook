import Foundation
import UIKit

/// Fallback của `fetch` (`_nativeSyncFetch`): request GET không body thất bại vì lỗi mạng, hết giờ hoặc HTTP 403/429/503
/// thì tự nạp lại cùng URL bằng browser ẩn (`HiddenBrowserFetch`, giải phóng ngay sau lượt đó).
/// - Browser thành công ⇒ script nhận response 200 với nội dung của trang (`html`, `raw`, `Content-Type`, `url` cuối).
/// - Browser cũng lỗi ⇒ trả **nguyên** response lỗi của fetch, chỉ `statusText` gộp thêm `" | Browser ẩn: <lý do>"`.
/// - Huỷ giữa chừng ⇒ trả nguyên response lỗi của fetch.
///
/// Không bao giờ chạy khi: cờ `allowsFetchBrowserFallback` tắt (TTS cần âm thanh, ảnh comic cần ảnh — trang HTML không
/// thay được), execution đã huỷ, POST/có body, nhánh tên miền bị chặn / 499 (trả sớm trong `_nativeSyncFetch`), hoặc đang
/// ở main thread (chờ semaphore trong khi WebKit cần main ⇒ deadlock).
extension JSExecutor {
    /// Mã coi là "bị chặn / tạm từ chối" — đáng thử bằng browser thật (Cloudflare trả 403/503, giới hạn tần suất 429).
    static let browserFallbackStatusCodes: Set<Int> = [403, 429, 503]
    /// Chờ lâu nhất để có suất browser khi đã có `HiddenBrowserFetch.maxConcurrent` browser khác chạy; hết suất ⇒ thất bại
    /// (lý do gộp vào `statusText` như mọi lỗi browser khác) thay vì giữ luồng JS lâu.
    private static let browserSlotWaitLimit: TimeInterval = 3
    private static let browserWaitSlice: TimeInterval = 0.25
    /// Header của script không chép sang request của browser: UA/cookie để WebKit tự lo (UA của webview, kho cookie có
    /// `cf_clearance`), còn lại là header tầng vận chuyển.
    private static let browserSkippedHeaders: Set<String> = [
        "user-agent", "cookie", "content-type", "content-length", "host", "accept-encoding", "connection"
    ]

    /// Gọi đúng một chỗ: cuối `_nativeSyncFetch`, trên luồng đang chạy JS. Không đủ điều kiện ⇒ trả `response` y nguyên.
    internal func applyingFetchBrowserFallback(
        to response: [String: Any],
        request: URLRequest,
        error: Error?,
        timedOut: Bool
    ) -> [String: Any] {
        guard let trigger = Self.browserFallbackTrigger(
                status: response["status"] as? Int ?? 0, error: error, timedOut: timedOut),
              allowsFetchBrowserFallback,
              (request.httpMethod ?? "GET").uppercased() == "GET",
              request.httpBody?.isEmpty ?? true,
              let url = request.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              !isCurrentExecutionCancelled else {
            return response
        }
        let target = Self.logTarget(url)
        guard !Thread.isMainThread else {
            AppLogger.shared.log("[JSFetch] \(trigger) \(target) — bỏ qua browser ẩn: fetch đang chạy trên main thread (chờ browser sẽ deadlock)")
            return response
        }

        AppLogger.shared.log("❌ [JSFetch] \(trigger) \(target) — đang thử mở browser ẩn…")
        let taskID = reserveNetworkTaskID()
        let startedAt = Date()
        emitDebugFetchStarted(taskID: taskID, url: url.absoluteString, method: "BROWSER")

        switch waitForHiddenBrowser(Self.browserRequest(from: request, url: url)) {
        case .success(let page):
            let (raw, charset) = Self.encodeRaw(page.content, characterSet: page.characterSet)
            let mime = page.contentType.isEmpty ? "text/html" : page.contentType
            let statusPart = page.httpStatus.map { ", HTTP \($0)" } ?? ""
            AppLogger.shared.log("✅ [JSFetch] Browser ẩn tải được \(target) (\(page.content.count) ký tự\(statusPart))")
            emitDebugFetchFinished(
                taskID: taskID, url: page.finalURL, status: page.httpStatus ?? 200,
                statusText: "Browser ẩn", bytes: raw.count, startedAt: startedAt
            )
            return [
                "html": page.content,
                "status": 200,
                "statusText": "OK",
                "raw": raw.base64EncodedString(),
                "headers": ["Content-Type": "\(mime); charset=\(charset)"],
                "url": page.finalURL.isEmpty ? url.absoluteString : page.finalURL
            ]
        case .failure(let reason, let httpStatus):
            AppLogger.shared.log("❌ [JSFetch] Fetch lỗi (\(trigger)) và browser ẩn cũng lỗi (\(reason)) — \(target)")
            emitDebugFetchFinished(
                taskID: taskID, url: url.absoluteString, status: httpStatus.flatMap { $0 >= 400 ? $0 : nil } ?? 0,
                statusText: "Browser ẩn: \(reason)", bytes: 0, startedAt: startedAt
            )
            let fetchText = (response["statusText"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? trigger
            var merged = response
            merged["statusText"] = "\(fetchText) | Browser ẩn: \(reason)"
            return merged
        case .cancelled:
            AppLogger.shared.log("[JSFetch] Execution bị huỷ khi đang chờ browser ẩn — trả lỗi fetch gốc \(target)")
            emitDebugFetchFinished(
                taskID: taskID, url: url.absoluteString, status: 499,
                statusText: "Browser ẩn: huỷ", bytes: 0, startedAt: startedAt
            )
            return response
        }
    }

    /// Nhãn lỗi fetch ("Hết giờ" / "<domain> <code>: <mô tả>" / "HTTP 403"), `nil` ⇒ không kích hoạt fallback.
    /// Hết giờ xét theo cờ của semaphore: sau khi hết giờ `_nativeSyncFetch` huỷ task nên callback mang lỗi -999.
    /// -999 ngoài ca đó chỉ do huỷ execution ⇒ không bao giờ là lỗi mạng.
    private static func browserFallbackTrigger(status: Int, error: Error?, timedOut: Bool) -> String? {
        if timedOut { return "Hết giờ" }
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return nil }
            return WebViewLoader.errorSummary(nsError)
        }
        return browserFallbackStatusCodes.contains(status) ? "HTTP \(status)" : nil
    }

    /// Chặn luồng JS tới khi browser kết luận. Chờ theo lát để còn kiểm huỷ; hết `timeout + 3 s` (main không phản hồi)
    /// thì bỏ cuộc — driver vẫn tự kết thúc và dọn dẹp ở hạn của nó.
    private func waitForHiddenBrowser(_ request: URLRequest) -> HiddenBrowserFetch.Outcome {
        let isCancelled: () -> Bool = { [weak self] in self?.isCurrentExecutionCancelled ?? true }
        guard HiddenBrowserFetch.acquireSlot(waitLimit: Self.browserSlotWaitLimit, isCancelled: isCancelled) else {
            if isCancelled() { return .cancelled }
            return .failure(reason: "đang có \(HiddenBrowserFetch.maxConcurrent) browser ẩn chạy", httpStatus: nil)
        }

        let lock = NSLock()
        var result: HiddenBrowserFetch.Outcome?
        var delivered = false
        let semaphore = DispatchSemaphore(value: 0)
        let deliver: (HiddenBrowserFetch.Outcome) -> Void = { outcome in
            lock.lock()
            defer { lock.unlock() }
            guard !delivered else { return }
            delivered = true
            result = outcome
            semaphore.signal()
        }

        let localPath = self.localPath
        DispatchQueue.main.async {
            // Luồng JS đã bỏ cuộc (huỷ / quá hạn) hoặc execution đã huỷ ⇒ không mở browser nữa.
            lock.lock()
            let abandoned = delivered
            lock.unlock()
            if abandoned || isCancelled() {
                HiddenBrowserFetch.releaseSlot()
                deliver(.cancelled)
                return
            }
            // App ở nền: WebKit tạm dừng tiến trình WebContent ⇒ browser chắc chắn hết giờ mà vẫn giữ suất + luồng JS
            // (TTS nền vẫn tải chương).
            if MainActor.assumeIsolated({ UIApplication.shared.applicationState == .background }) {
                HiddenBrowserFetch.releaseSlot()
                deliver(.failure(reason: "app đang ở nền", httpStatus: nil))
                return
            }
            HiddenBrowserFetch.start(
                request: request, extensionLocalPath: localPath, isCancelled: isCancelled, completion: deliver
            )
        }

        let giveUpAt = Date().addingTimeInterval(HiddenBrowserFetch.timeout + 3)
        while semaphore.wait(timeout: .now() + Self.browserWaitSlice) == .timedOut {
            if isCancelled() {
                deliver(.cancelled)
                break
            }
            if Date() >= giveUpAt {
                deliver(.failure(reason: "hết giờ (main thread không phản hồi)", httpStatus: nil))
                break
            }
        }

        lock.lock()
        defer { lock.unlock() }
        return result ?? .cancelled
    }

    private static func browserRequest(from request: URLRequest, url: URL) -> URLRequest {
        var browserRequest = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: HiddenBrowserFetch.timeout)
        for (key, value) in request.allHTTPHeaderFields ?? [:]
        where !browserSkippedHeaders.contains(key.lowercased()) {
            browserRequest.setValue(value, forHTTPHeaderField: key)
        }
        return browserRequest
    }

    /// `raw` = byte theo đúng bảng mã của trang (vd GBK) để `.text("gbk")` / `.html("gbk")` của script giải ra đúng như
    /// với byte gốc từ máy chủ. Họ GBK mã hoá bằng GB18030 — đúng bảng mà `_nativeDecodeBase64` dùng để giải. Ký tự không
    /// mã hoá được ⇒ mã hoá lossy; bảng mã lạ ⇒ UTF-8. Trả kèm tên charset cho `Content-Type`.
    private static func encodeRaw(_ content: String, characterSet: String) -> (Data, String) {
        let name = characterSet.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, name != "utf-8", name != "utf8" else { return (Data(content.utf8), "utf-8") }
        let cfEncoding: CFStringEncoding
        if ["gbk", "gb2312", "gb18030", "x-gbk"].contains(name) {
            cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        } else {
            cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        }
        guard cfEncoding != kCFStringEncodingInvalidId else { return (Data(content.utf8), "utf-8") }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        if let data = content.data(using: encoding) ?? content.data(using: encoding, allowLossyConversion: true) {
            return (data, name)
        }
        return (Data(content.utf8), "utf-8")
    }

    /// `host + path` — không log query (có thể chứa token).
    private static func logTarget(_ url: URL) -> String {
        "\(url.host ?? "")\(url.path)"
    }
}
