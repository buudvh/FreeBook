import Foundation

/// Bộ phân xử "lỗi do ai" của một bước hỏng — **hàm thuần**, dùng chung cho bộ chạy hàng loạt (`LegadoCorpusProbe`)
/// và màn Gỡ lỗi từng bước (`LegadoSourceDebugRunner`). Đầu vào gom ở `Evidence` (`+Evidence` dựng từ lỗi + run log).
///
/// Luật theo thứ tự ưu tiên, **dừng ở luật đầu khớp**; không đủ bằng chứng ⇒ `unknown`, không đoán:
///
/// | # | Kết luận | Khi nào |
/// |---|---|---|
/// | 1 | `needsUser` | trang của bước (đầu dò: thân đầy đủ; vết request: 4 KB đầu) là thử thách/captcha (`LegadoPageMarker`: Cloudflare `cf-chl`, tiêu đề "Just a moment"/"Attention Required", `challenge-platform`/"Just a moment" kèm ≥ 400; "captcha"/"安全验证"/"人机验证" ở `<title>` hay trang nhỏ/≥ 400); nguồn có `loginUrl` và HTTP 401/403; engine ghi "startBrowser…/getVerificationCode… (không có người dùng)" |
/// | 2 | `web` | trang chặn ("区域被禁止", "1Panel" ⇒ chặn theo vùng; "访问被拒绝", "Access denied", "403 Forbidden" ⇒ từ chối); lỗi mạng (trừ máy mất mạng); engine quá thời gian; vượt trần bộ chạy mà request cuối không có phản hồi; HTTP 403, 404 **ở bước đầu**, 410, 429, 451, 5xx |
/// | 3 | `app` | cú pháp/hàm chưa hỗ trợ (trừ lớp dò app `io.legado.*`/`io.legato.*`); lỗi JS chỉ vào phần giả lập (`java.`, `source.`, `book.`, `chapter.`, `cookie.`, `cache.`, `org.jsoup`, `Packages` + "is not a function"/"undefined is not"/"Chưa hỗ trợ"); rule khớp 0 trên trang 2xx không phải JSON, không JS sau bộ chọn, và có vế rule mà **mọi** class/id đều có trong trang, thẻ cuối của vế (`li` trong `.list li`) có sau phần tử chứa (nội dung: phần tử khớp có ≥ `minimumElementText` ký tự chữ) |
/// | 4 | `sourceOutdated` | rule khớp 0 trên trang 2xx không phải JSON, rule có class/id mà **không** token nào có trong trang; nguồn thiếu rule / không có lối vào / không có URL gốc |
/// | 5 | `unknown` | còn lại, kèm lý do cụ thể (lỗi JS của script nguồn, rule toàn JS/JSONPath, khớp một phần…) |
///
/// Lý do (`reason`) chỉ gồm câu cố định + số đếm + token của rule + đoạn thông điệp đã redact — không URL đầy đủ,
/// không thân trang, cookie hay header (đi vào báo cáo chia sẻ được).
enum LegadoFailureArbiter {
    /// Lỗi của bước, đã quy về những gì bộ phân xử cần.
    enum ErrorKind: Sendable, Equatable {
        case unsupported(String)
        case http(Int)
        /// Engine báo quá thời gian (15 s/request).
        case timeout
        /// Bước vượt trần của bộ chạy (giây).
        case stepDeadline(Int)
        case network(String)
        case javaScript(String)
        /// Rule khớp 0 / bước ra rỗng.
        case noMatch(String)
        /// Nguồn thiếu rule, không có lối vào, không có URL gốc.
        case sourceDefect(String)
        /// Không chạy được nguồn vì lý do khác (không đọc được `source.json`, URL hỏng…).
        case invalidSource(String)
        case other(String)
    }

    /// Một vết request rút gọn: mã HTTP (`nil` = không có phản hồi), kích thước, đoạn đầu thân, lỗi.
    struct Request: Sendable, Equatable {
        let statusCode: Int?
        let byteCount: Int
        let body: String
        let errorMessage: String?
    }

    struct Evidence: Sendable {
        var error: ErrorKind
        /// Bước tìm kiếm (0 mục còn có thể do từ khoá không có kết quả).
        var isSearchStep: Bool
        /// Chưa bước nào qua (HTTP 404 ở bước đầu = web; ở bước sau = URL do rule dựng).
        var isFirstStep: Bool
        /// Vết request của **bước hỏng**, theo thứ tự gửi.
        var requests: [Request]
        /// Đầu dò bộ chọn cuối cùng của bước (khi bước danh sách/nội dung ra rỗng).
        var probe: LegadoSelectorProbe?
        var hasLoginUrl: Bool
        /// Thông điệp chẩn đoán của engine trong bước.
        var diagnostics: [String]
    }

    struct Judgement: Sendable, Equatable {
        let verdict: LegadoFailureVerdict
        let reason: String
    }

    /// Phần tử nội dung có ít nhất ngần này ký tự chữ trong HTML gốc mà rule ra rỗng ⇒ nghi app.
    static let minimumElementText = 50

    static func judge(_ evidence: Evidence) -> Judgement {
        if let judgement = needsUser(evidence) { return judgement }
        if let judgement = web(evidence) { return judgement }
        if let judgement = app(evidence) { return judgement }
        if let judgement = sourceOutdated(evidence) { return judgement }
        return unknown(evidence)
    }

    // MARK: - 1. Cần người dùng

    private static func needsUser(_ evidence: Evidence) -> Judgement? {
        if let marker = markers(evidence).first(where: { $0.needsUser }) {
            return Judgement(verdict: .needsUser, reason: sentence(marker.reason) + statusSuffix(evidence))
        }
        if evidence.hasLoginUrl, let code = failingStatus(evidence), code == 401 || code == 403 {
            return Judgement(verdict: .needsUser,
                             reason: "Nguồn cần đăng nhập (HTTP \(code)) — đăng nhập ở màn chi tiết nguồn rồi thử lại")
        }
        if evidence.diagnostics.contains(where: isInteractionSkip) {
            return Judgement(verdict: .needsUser,
                             reason: "Nguồn cần mở trình duyệt / nhập mã xác minh — chỉ chạy được khi bạn mở truyện từ màn đọc")
        }
        return nil
    }

    /// "java.startBrowser bỏ qua (không có người dùng)", "getVerificationCode: … (không có người dùng)". `java.openUrl`
    /// bỏ qua không phải nhu cầu xác minh.
    private static func isInteractionSkip(_ message: String) -> Bool {
        message.contains("không có người dùng")
            && (message.contains("startBrowser") || message.contains("getVerificationCode"))
    }

    // MARK: - 2. Web

    private static func web(_ evidence: Evidence) -> Judgement? {
        if let marker = markers(evidence).first(where: { !$0.needsUser }) {
            return Judgement(verdict: .web, reason: sentence(marker.reason) + statusSuffix(evidence))
        }
        switch evidence.error {
        case .network(let message):
            guard !isOffline(message) else { return nil }
            return Judgement(verdict: .web, reason: networkReason(message))
        case .timeout:
            return Judgement(verdict: .web, reason: "Web không trả lời — quá thời gian chờ")
        case .stepDeadline(let seconds):
            guard let last = evidence.requests.last, last.statusCode == nil else { return nil }
            return Judgement(verdict: .web,
                             reason: "Web không trả lời — bước chạy quá \(seconds) giây, request cuối không có phản hồi")
        case .http(let code):
            return httpJudgement(code, isFirstStep: evidence.isFirstStep)
        default:
            return nil
        }
    }

    private static func httpJudgement(_ code: Int, isFirstStep: Bool) -> Judgement? {
        let reason: String
        switch code {
        case 403: reason = "HTTP 403 — web từ chối truy cập"
        case 404 where isFirstStep: reason = "HTTP 404 — trang không tồn tại (web đã đổi địa chỉ hoặc ngừng hoạt động)"
        case 410: reason = "HTTP 410 — trang đã bị gỡ"
        case 429: reason = "HTTP 429 — web giới hạn tần suất truy cập"
        case 451: reason = "HTTP 451 — bị chặn vì lý do pháp lý"
        case 500...599: reason = "HTTP \(code) — máy chủ web lỗi hoặc quá tải"
        default: return nil
        }
        return Judgement(verdict: .web, reason: reason)
    }

    /// Thông điệp lỗi mạng là `localizedDescription` của hệ thống (đổi theo ngôn ngữ máy) — chỉ nhận vài dấu hiệu phổ
    /// biến, còn lại ghi chung "không kết nối được" kèm thông điệp gốc.
    private static func networkReason(_ message: String) -> String {
        let lower = message.lowercased()
        let detail = clip(message, limit: 120)
        if ["hostname", "tên máy chủ", "主机名", "dns"].contains(where: { lower.contains($0) }) {
            return "Tên miền không tồn tại hoặc không phân giải được — " + detail
        }
        if ["ssl", "tls", "certificate", "chứng chỉ", "证书", "secure connection", "kết nối an toàn"].contains(where: { lower.contains($0) }) {
            return "Lỗi TLS / chứng chỉ của web — " + detail
        }
        return "Không kết nối được máy chủ web — " + detail
    }

    private static func isOffline(_ message: String) -> Bool {
        let lower = message.lowercased()
        return ["offline", "ngoại tuyến", "not connected to the internet", "离线"].contains(where: { lower.contains($0) })
    }

    // MARK: - 3. App

    private static func app(_ evidence: Evidence) -> Judgement? {
        switch evidence.error {
        case .unsupported(let what) where !isAppProbe(what):
            return Judgement(verdict: .app, reason: "Chưa hỗ trợ ở bản này: " + clip(stripUnsupportedPrefix(what)))
        case .javaScript(let message) where pointsToAppShim(message):
            return Judgement(verdict: .app, reason: "Lỗi ở phần giả lập của app: " + clip(message))
        case .noMatch:
            break
        default:
            return nil
        }
        guard let probe = usableProbe(evidence) else { return nil }
        if probe.isList {
            guard probe.matchedElements == 0, !probe.hasScript, probe.hasStructureMatch else { return nil }
            return Judgement(verdict: .app, reason: "Trang tải được (\(pageSummary(probe))) và có "
                + presentSummary(probe.presentTokens) + ", nhưng rule \(fieldLabel(probe)) ra 0 mục")
        }
        guard !probe.hasScript, let length = probe.elementTextLength, length >= minimumElementText,
              let token = probe.presentTokens.first else { return nil }
        return Judgement(verdict: .app, reason: "Trang tải được (\(pageSummary(probe))) và phần tử \(token.label) có khoảng "
            + "\(length) ký tự chữ, nhưng rule nội dung ra rỗng")
    }

    /// Lớp nội bộ của app Legado khác mà script tạo thử để dò đang chạy trên app nào (spec §6.10) — không phải tính
    /// năng nguồn cần.
    private static func isAppProbe(_ text: String) -> Bool {
        text.contains("io.legado.") || text.contains("io.legato.")
    }

    /// Lỗi JS chỉ vào đối tượng do app giả lập (không phải biến của chính script).
    private static func pointsToAppShim(_ message: String) -> Bool {
        guard !isAppProbe(message) else { return false }
        let shims = ["java.", "source.", "book.", "chapter.", "cookie.", "cache.", "org.jsoup", "Packages"]
        let failures = ["is not a function", "undefined is not", "Chưa hỗ trợ"]
        return shims.contains(where: { message.contains($0) }) && failures.contains(where: { message.contains($0) })
    }

    private static func stripUnsupportedPrefix(_ text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.hasPrefix("Chưa hỗ trợ ") { output = String(output.dropFirst("Chưa hỗ trợ ".count)) }
        if output.hasSuffix(" ở bản này") { output = String(output.dropLast(" ở bản này".count)) }
        return output
    }

    // MARK: - 4. Nguồn lỗi thời

    private static func sourceOutdated(_ evidence: Evidence) -> Judgement? {
        if case .sourceDefect(let message) = evidence.error {
            return Judgement(verdict: .sourceOutdated, reason: "Nguồn thiếu rule / cấu hình hỏng: " + clip(message))
        }
        switch evidence.error {
        case .noMatch, .javaScript: break
        default: return nil
        }
        guard let probe = usableProbe(evidence), probe.hasSelectorTokens, probe.presentTokens.isEmpty,
              (probe.matchedElements ?? 0) == 0 else { return nil }
        let hint = evidence.isSearchStep
            ? " — trang đã đổi giao diện, hoặc từ khoá không có kết quả"
            : " — trang đã đổi giao diện"
        return Judgement(verdict: .sourceOutdated, reason: "Trang tải được (\(pageSummary(probe))) nhưng không có phần tử "
            + "nào khớp " + labels(probe.missingTokens) + hint)
    }

    // MARK: - 5. Chưa rõ

    private static func unknown(_ evidence: Evidence) -> Judgement {
        if case .noMatch = evidence.error, let probe = evidence.probe,
           let reason = probeUnknownReason(probe, isSearchStep: evidence.isSearchStep) {
            return Judgement(verdict: .unknown, reason: reason)
        }
        let reason: String
        switch evidence.error {
        case .javaScript(let message):
            reason = "Lỗi JS trong script của nguồn: " + clip(message)
        case .unsupported(let what):
            reason = "Script nguồn dò biến thể app rồi dừng: " + clip(what)
        case .http(let code):
            reason = code == 404
                ? "HTTP 404 ở bước sau — URL do rule dựng không còn tồn tại (nguồn lỗi thời?) hoặc app ghép URL sai"
                : "HTTP \(code)"
        case .network(let message):
            reason = isOffline(message) ? "Máy đang mất mạng — thử lại" : "Lỗi mạng: " + clip(message)
        case .stepDeadline(let seconds):
            reason = "Bước chạy quá \(seconds) giây (vòng JS hoặc quá nhiều trang) — đã bỏ chờ"
        case .noMatch(let what):
            reason = "Rule không khớp (\(clip(what, limit: 80))) — không có trang HTML để đối chiếu"
        case .invalidSource(let message):
            reason = "Không chạy được nguồn: " + clip(message)
        case .other(let message):
            let text = clip(message)
            reason = text.isEmpty ? "Không đủ bằng chứng để kết luận" : text
        case .timeout, .sourceDefect:
            reason = "Không đủ bằng chứng để kết luận"
        }
        return Judgement(verdict: .unknown, reason: reason)
    }

    private static func probeUnknownReason(_ probe: LegadoSelectorProbe, isSearchStep: Bool) -> String? {
        let field = fieldLabel(probe)
        if !probe.isPageLoaded {
            return "Trang trả HTTP \(probe.statusCode) — rule \(field) ra rỗng"
        }
        if probe.isJSON {
            return "Trang trả JSON — rule \(field) ra rỗng, không dò được bằng bộ chọn"
        }
        if !probe.hasSelectorTokens {
            return "Rule \(field) không có class/id để đối chiếu (JS, JSONPath, XPath hoặc chỉ tên thẻ) — không đủ bằng chứng"
        }
        if let matched = probe.matchedElements, matched > 0 {
            return "Rule \(field) khớp \(matched) phần tử nhưng không mục nào có tên/link — kiểm các rule trường"
        }
        let present = probe.presentTokens
        if probe.hasScript, !present.isEmpty {
            return "Trang có " + presentSummary(present) + " nhưng JS sau bộ chọn của rule \(field) cho kết quả rỗng"
                + " — do JS của nguồn hoặc app"
        }
        if let tag = probe.missingTrailingTag {
            let hint = isSearchStep ? "có thể từ khoá không có kết quả" : "cấu trúc trang có thể đã đổi"
            return "Trang có " + labels(present) + " nhưng không thấy <\(tag)> bên trong — " + hint
        }
        if !probe.isList, let token = present.first {
            return "Trang có phần tử \(token.label) nhưng gần như không có chữ — trang có thể tải nội dung bằng JS "
                + "(nguồn cần webView) hoặc app trích sai"
        }
        if !present.isEmpty {
            return "Trang chỉ có một phần bộ chọn của rule \(field): có " + labels(present)
                + ", không có " + labels(probe.missingTokens)
        }
        return nil
    }

    // MARK: - Tiện ích

    /// Dấu hiệu trang chặn/thử thách: từ đầu dò (thân đầy đủ) rồi tới vết request (mới nhất trước).
    private static func markers(_ evidence: Evidence) -> [LegadoPageMarker] {
        var output: [LegadoPageMarker] = []
        if let marker = evidence.probe?.marker { output.append(marker) }
        for request in evidence.requests.reversed() {
            if let marker = LegadoPageMarker.detect(body: request.body, statusCode: request.statusCode,
                                                    byteCount: request.byteCount) {
                output.append(marker)
            }
        }
        return output
    }

    /// Mã HTTP lỗi của bước: từ lỗi, không có thì request cuối có mã ≥ 400.
    private static func failingStatus(_ evidence: Evidence) -> Int? {
        if case .http(let code) = evidence.error { return code }
        if let code = evidence.requests.last?.statusCode, code >= 400 { return code }
        return nil
    }

    private static func statusSuffix(_ evidence: Evidence) -> String {
        if let code = failingStatus(evidence) { return " (HTTP \(code))" }
        if let probe = evidence.probe, probe.marker != nil { return " (HTTP \(probe.statusCode))" }
        return ""
    }

    /// Đầu dò dùng được làm bằng chứng: trang 2xx, không JSON, không phải trang chặn/thử thách.
    private static func usableProbe(_ evidence: Evidence) -> LegadoSelectorProbe? {
        guard let probe = evidence.probe, probe.isPageLoaded, !probe.isJSON, probe.marker == nil else { return nil }
        return probe
    }

    private static func fieldLabel(_ probe: LegadoSelectorProbe) -> String {
        switch probe.field {
        case "bookList": return "danh sách"
        case "chapterList": return "mục lục"
        case "content": return "nội dung"
        default: return probe.field
        }
    }

    /// "HTTP 200, 12 KB".
    private static func pageSummary(_ probe: LegadoSelectorProbe) -> String {
        "HTTP \(probe.statusCode), \(max(1, (probe.byteCount + 1023) / 1024)) KB"
    }

    /// "12 phần tử khớp .bookbox" / "phần tử khớp .a ×3, #b ×1".
    private static func presentSummary(_ tokens: [LegadoSelectorProbe.Token]) -> String {
        let shown = Array(tokens.prefix(3))
        if shown.count == 1, let token = shown.first {
            return "\(token.count) phần tử khớp \(token.label)"
        }
        return "phần tử khớp " + shown.map { "\($0.label) ×\($0.count)" }.joined(separator: ", ")
    }

    private static func labels(_ tokens: [LegadoSelectorProbe.Token]) -> String {
        let shown = tokens.prefix(4).map(\.label).joined(separator: ", ")
        return tokens.count > 4 ? shown + "…" : shown
    }

    private static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + String(text.dropFirst())
    }

    /// Thông điệp tự do ⇒ redact URL (giá trị query, khối option) rồi cắt ngắn.
    static func clip(_ text: String, limit: Int = 160) -> String {
        let redacted = LegadoCorpusErrorClassifier.redact(text)
        guard redacted.count > limit else { return redacted }
        return String(redacted.prefix(limit)) + "…"
    }
}
