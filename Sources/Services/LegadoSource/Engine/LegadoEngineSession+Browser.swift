import Foundation

/// `java.startBrowser`, `startBrowserAwait`, `startBrowserDp`, `getVerificationCode` (spec §10.8, §9.6).
///
/// Thread engine phát yêu cầu qua `LegadoPresentationEventCenter` rồi **chờ ngoài main** (semaphore theo lát, có hạn
/// giờ và kiểm huỷ). Phiên không có người dùng hoặc chưa có presenter ⇒ không mở gì: `startBrowser` chỉ ghi log,
/// `startBrowserAwait` trả phản hồi rỗng (`code() == 0`), `getVerificationCode` trả `""`.
extension LegadoEngineSession {
    static let browserAwaitTimeout: TimeInterval = 600
    static let verificationTimeout: TimeInterval = 300

    /// Có trình bày UI được không.
    var canPresentUserInterface: Bool {
        allowsUserInteraction && LegadoPresentationEventCenter.shared.hasPresenter
    }

    /// `java.startBrowser(url, title)` / `startBrowserDp`: mở và **không chờ**; cookie được gộp vào kho khi người dùng đóng.
    /// Nội dung video (`capturesBrowserAsPlaybackCandidate`) ⇒ ghi ứng viên phát thay vì mở (§9.6).
    func jsStartBrowser(url: String, title: String) {
        if capturesBrowserAsPlaybackCandidate {
            playbackCandidates.append(LegadoPlaybackCandidate(url: url, title: title))
            diagnostics.record(.info, "startBrowser → ứng viên phát: \(url.prefix(160))")
            return
        }
        guard canPresentUserInterface else {
            diagnostics.record(.info, "java.startBrowser bỏ qua (không có người dùng): \(url.prefix(160))")
            return
        }
        let request = makeBrowserRequest(url: url, title: title, html: nil, waits: false)
        let jar = cookieJar
        let ticket = LegadoPresentationTicket(id: request.id, event: .browser(request)) { ticket in
            if let result = ticket.browserResult { jar.absorbStored(result.cookies) }
        }
        LegadoPresentationEventCenter.shared.enqueue(ticket)
    }

    /// `java.startBrowserAwait(url, title[, refetch = true[, html]])`: chặn tới khi người dùng đóng. `refetch` (U45):
    /// sau khi đồng bộ cookie, tải lại `url` bằng HTTP và trả phản hồi đó; `false` ⇒ trả trạng thái trang lúc đóng
    /// (`body()` = outerHTML, `url()` = URL hiện tại, `code()` = 200). `nil` ⇒ không có người dùng / hết giờ (mã 0).
    func jsStartBrowserAwait(url: String, title: String, refetch: Bool, html: String?) throws -> LegadoHTTPResponse? {
        guard canPresentUserInterface else {
            diagnostics.record(.info, "java.startBrowserAwait: cần xác minh thủ công (không có người dùng)")
            return nil
        }
        let request = makeBrowserRequest(url: url, title: title, html: html, waits: true)
        let ticket = LegadoPresentationTicket(id: request.id, event: .browser(request))
        LegadoPresentationEventCenter.shared.enqueue(ticket)
        guard let finished = try waitForUser(ticket, timeout: Self.browserAwaitTimeout),
              let result = finished.browserResult else { return nil }
        cookieJar.absorbStored(result.cookies)
        if refetch, html == nil, !LegadoDataURL.isDataURL(request.url), let response = try jsConnect(url, headers: nil) {
            return response
        }
        let finalURL = result.finalURL.isEmpty ? request.url : result.finalURL
        return LegadoHTTPResponse(requestURL: request.url, finalURL: finalURL, statusCode: 200, headers: [:], cookies: [:],
                                  body: result.html, data: Data(result.html.utf8))
    }

    /// `java.getVerificationCode(imageUrl)`: ảnh tải bằng client của nguồn (cùng phiên cookie); huỷ/hết giờ ⇒ `""`.
    func jsVerificationCode(imageURL: String) throws -> String {
        guard canPresentUserInterface else {
            diagnostics.record(.info, "java.getVerificationCode: cần nhập mã thủ công (không có người dùng)")
            return ""
        }
        var imageData: Data?
        var mime: String?
        if let decoded = LegadoDataURL.decode(imageURL) {
            imageData = decoded.bytes
            mime = decoded.mime
        } else {
            do {
                let request = try buildRequest(imageURL, baseUrl: currentFrameBaseUrl)
                let response = try perform(request, allowHTTPError: true)
                imageData = response.data
                mime = response.header("Content-Type")
            } catch {
                if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
                diagnostics.record(.network, "Ảnh mã xác minh: \(error.localizedDescription)")
            }
        }
        let request = LegadoVerificationRequest(id: UUID(), sourceKey: source.key, sourceName: source.name,
                                                imageURL: imageURL, imageData: imageData, imageMimeType: mime)
        let ticket = LegadoPresentationTicket(id: request.id, event: .verificationCode(request))
        LegadoPresentationEventCenter.shared.enqueue(ticket)
        guard let finished = try waitForUser(ticket, timeout: Self.verificationTimeout) else { return "" }
        return finished.verificationCode ?? ""
    }

    /// Yêu cầu trình duyệt cho `url` (tương đối ⇒ ghép theo trang đang phân tích): header nguồn + đăng nhập, UA, cookie.
    func makeBrowserRequest(url: String, title: String, html: String?, waits: Bool) -> LegadoBrowserRequest {
        let base = currentFrameBaseUrl ?? sourceBase
        let target = LegadoDataURL.isDataURL(url) ? url : LegadoURLResolver.absolute(url, base: base)
        var headerMap: [String: String] = [:]
        if let pairs = try? sourceHeaders(baseUrl: currentFrameBaseUrl) {
            for pair in pairs { headerMap[pair.name] = pair.value }
        }
        for pair in loginHeaders(forURL: target, pageURL: currentFrameBaseUrl) {
            headerMap[pair.name] = pair.value
        }
        let userAgent = headerMap.first { $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame }?.value
            ?? LegadoHTTPClient.webViewUserAgent
        return LegadoBrowserRequest(id: UUID(), sourceKey: source.key, sourceName: source.name, url: target,
                                    title: title, html: html, waitsForResult: waits, userAgent: userAgent,
                                    headers: headerMap, cookies: cookieJar.storedCookies(forURL: target))
    }

    /// Chờ người dùng trả lời (ngoài main). Hết giờ ⇒ `nil` + báo presenter đóng; phiên bị huỷ ⇒ ném `CancellationError`.
    func waitForUser(_ ticket: LegadoPresentationTicket, timeout: TimeInterval) throws -> LegadoPresentationTicket? {
        let center = LegadoPresentationEventCenter.shared
        let answered: Bool
        do {
            answered = try cancellation.wait(ticket.semaphore, timeout: timeout)
        } catch {
            center.cancel(ticket.id)
            throw error
        }
        guard answered else {
            center.cancel(ticket.id)
            diagnostics.record(.info, "Hết giờ chờ người dùng xác minh")
            return nil
        }
        return ticket
    }

    /// `java.toast/longToast`: phiên có người dùng ⇒ gửi sự kiện cho UI (nếu lớp gọi không tự gắn `onToast`).
    func forwardToast(_ message: String, isLong: Bool) {
        guard onToast == nil, allowsUserInteraction else { return }
        LegadoPresentationEventCenter.shared.send(.toast(message: message, sourceName: source.name, isLong: isLong))
    }
}
