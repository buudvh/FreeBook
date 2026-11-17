import Foundation

/// **Nơi duy nhất** chứa hợp đồng với trang ChatGPT (`chatgpt.com`, 1.3.971): URL, selector, mã JS chạy trong trang và
/// cách đọc câu trả lời — cho **cả hai** kiểu trang. ChatGPT đổi cấu trúc thì sửa đúng file này; lỗi hiện ra là
/// `ChatGPTWebError.protocolChanged(<vị trí>)`.
///
/// **Trang ẩn danh bản mobile** — đã thử thật 2026-11-17 (Chromium giả lập mobile, chưa đăng nhập, 5 tin):
/// - trang server-render riêng (`/unauth-mweb/…`), không phải app React của bản đăng nhập;
/// - ô nhập `textarea[data-mobile-composer-prompt]` (không `maxlength`; thử 12.166 ký tự gửi và trả lời được). Gán chữ
///   bằng setter gốc + sự kiện `input`; gửi bằng `form.requestSubmit(nút)` — nút `[data-composer-submit]` chỉ bật theo
///   khung hình vẽ (`requestAnimationFrame`), trang không được vẽ thì nút không bật nhưng `requestSubmit` vẫn gửi;
/// - nút gửi mang `aria-label` = `data-stop-label` trong lúc trả lời (chậm ~3 s mới trở lại sau khi xong);
/// - mỗi tin là `li[data-message-role="user|assistant"]`; tin trợ lý có `data-message-streaming` lúc đang viết và
///   `data-message-complete` khi xong; chữ nằm trong `[data-assistant-markdown-root]`;
/// - cổng chặn của máy chủ: `html[data-conversation-gated]` + `[data-gate-kind]` (`rate_limited` / `force_login` /
///   `forbidden`), nút thử lại có `data-retry-after`. Chưa gặp thật — đọc từ mã của trang;
/// - sau tin ẩn danh thứ 5 trang mở `dialog#mobile-auth-dialog` mời đăng nhập. App **không** tự đóng hộp này.
///
/// **Trang đã đăng nhập** — đã thử thật 2026-11-17 (Chrome máy tính, tài khoản Free, 3 tin chat tạm; **chưa** thử với UA
/// điện thoại):
/// - app React; ô nhập là vùng soạn thảo `form[data-chatgpt-composer] [contenteditable="true"]`. Gán chữ bằng sự kiện
///   `paste` tự dựng (`ClipboardEvent` + `DataTransfer`) — trang nhận và chặn mặc định; dự phòng
///   `execCommand('insertText')`;
/// - nút gửi `button[type="submit"]` chỉ có khi ô nhập có chữ (nhãn theo ngôn ngữ ⇒ không dò nhãn); gửi bằng
///   `form.requestSubmit(nút)`. Lúc đang trả lời nút đó bị thay bằng nút dừng `type="button"`;
/// - mỗi lượt (câu hỏi + câu trả lời) là một `[data-talvt-turn-state]` = `in_progress` → `complete`; lượt vừa gửi mang
///   `complete` trong tích tắc khi **chưa** có phần trợ lý ⇒ chỉ tin `complete` khi lượt đã có
///   `[data-conversation-role="assistant"]`; chữ nằm trong `[data-dil-response]` (có cả lúc đang viết);
/// - khối code là `[data-chatgpt-copy-code="<mã>"]` (không phải `<pre>`), phần đầu khối mang `data-markdown-copy="exclude"`.
///
/// **Không focus ô nhập** (1.3.976 — lỗi thật: mỗi lần WebView ẩn chạy là bàn phím bật lên). Phần tử trong trang được
/// focus thì WebKit mở phiên nhập cho WKWebView và giành bàn phím của app. Đã thử thật: gán chữ vào `textarea` và sự kiện
/// `paste` vào vùng soạn thảo đều chạy khi ô nhập **không** được focus; trang ẩn danh không tự focus, trang đã đăng nhập
/// tự focus vùng soạn thảo ⇒ `focusGuardScript` chặn ngay từ lúc document bắt đầu.
///
/// **Chung**: hai trang dùng cùng bộ dựng markdown (`data-d-component`) ⇒ một bộ đọc chữ `__collectText`. Xuống dòng mềm
/// là text node `"\n"` (`white-space: pre-line`) ⇒ **không** gộp `\n` thành dấu cách. Mọi lượt mở `?temporary-chat=true`:
/// đã đăng nhập thì là chat tạm (không vào lịch sử ChatGPT của người dùng), trang ẩn danh bỏ qua tham số. Cuộc chat ẩn
/// danh / chat tạm chỉ sống trong trang đang mở — nạp lại là mất (đã thử `/uc/<id>` bị đưa về `/`).
enum ChatGPTWebPageContract {
    static let host = "https://chatgpt.com"
    /// Trang chat mới của mọi lượt (chat tạm khi đã đăng nhập).
    static let homeURL = URL(string: "\(host)/?temporary-chat=true")!
    /// Trang mở trong trình duyệt bypass cho người dùng (đăng nhập, qua bước kiểm tra, xem thông báo).
    static let browserURL = URL(string: "\(host)/")!

    /// Ảnh chụp trạng thái trang mỗi nhịp đọc.
    struct Snapshot: Sendable {
        let path: String
        /// Trang là bản đã đăng nhập (app React) chứ không phải trang ẩn danh mobile.
        let signedIn: Bool
        /// Số tin của trợ lý trên trang.
        let turnCount: Int
        /// Chữ của tin trợ lý mới nhất (đã bỏ nút, phần ẩn). Rỗng khi tin chưa có khối chữ.
        let newestText: String
        let answerFound: Bool
        /// Tin trợ lý mới nhất đã xong (`data-message-complete` / lượt `complete` có phần trợ lý).
        let complete: Bool
        /// Tin trợ lý mới nhất đang được viết (`data-message-streaming` / lượt `in_progress`).
        let streaming: Bool
        /// Trang còn đang chạy một lượt (nút gửi đang là nút "Dừng" / lượt `in_progress`).
        let generating: Bool
        /// Trạng thái lạ của lượt mới nhất trên trang đã đăng nhập (khác `complete` / `in_progress`) — coi là lượt lỗi.
        let turnFailure: String
        let composerFound: Bool
        /// Script của trang đã gắn xong.
        let ready: Bool
        /// Số ký tự còn nằm trong ô nhập (gửi được thì trang tự xoá).
        let draftLength: Int
        let gated: Bool
        let gateKind: String
        let gateText: String
        let retryAfter: String
        /// Chữ của vùng báo lỗi gửi (`[data-composer-submission-status]`) khi nó đang hiện.
        let submitError: String
        /// Có `dialog[open]` — hộp mời đăng nhập của trang ẩn danh.
        let dialogOpen: Bool
        /// Trang kiểm tra của Cloudflare.
        let challenge: Bool
        let scriptError: String?

        init?(_ raw: Any?) {
            guard let dict = raw as? [String: Any] else { return nil }
            path = dict["path"] as? String ?? ""
            signedIn = (dict["signedIn"] as? Bool) ?? false
            turnCount = (dict["turnCount"] as? NSNumber)?.intValue ?? 0
            newestText = dict["text"] as? String ?? ""
            answerFound = (dict["answerFound"] as? Bool) ?? false
            complete = (dict["complete"] as? Bool) ?? false
            streaming = (dict["streaming"] as? Bool) ?? false
            generating = (dict["generating"] as? Bool) ?? false
            turnFailure = dict["turnFailure"] as? String ?? ""
            composerFound = (dict["composer"] as? Bool) ?? false
            ready = (dict["ready"] as? Bool) ?? false
            draftLength = (dict["draftLength"] as? NSNumber)?.intValue ?? 0
            gated = (dict["gated"] as? Bool) ?? false
            gateKind = dict["gateKind"] as? String ?? ""
            gateText = dict["gateText"] as? String ?? ""
            retryAfter = dict["retryAfter"] as? String ?? ""
            submitError = dict["submitError"] as? String ?? ""
            dialogOpen = (dict["dialogOpen"] as? Bool) ?? false
            challenge = (dict["challenge"] as? Bool) ?? false
            scriptError = dict["error"] as? String
        }

        /// Nhãn kiểu trang cho log.
        var kindLabel: String { signedIn ? "đã đăng nhập" : "ẩn danh" }
    }

    /// Kết quả của `submitScript`.
    enum SubmitOutcome: String, Sendable {
        case submitted
        case clicked
        /// Trang còn đang viết lượt trước — bấm lúc này là bấm "Dừng".
        case busy
        case noComposer = "no-composer"
        /// Chưa có nút gửi dùng được (trang đã đăng nhập chỉ dựng nút khi ô nhập có chữ).
        case noSubmit = "no-submit"

        var didSend: Bool { self == .submitted || self == .clicked }
    }

    // MARK: - Cổng chặn

    /// Lỗi ứng với cổng chặn trang đang hiện.
    static func gateError(_ snapshot: Snapshot) -> ChatGPTWebError {
        switch snapshot.gateKind {
        case "rate_limited":
            return .rateLimited(retryAfter: retryAfterSeconds(snapshot.retryAfter))
        case "force_login":
            return .loginRequired
        default:
            let detail = snapshot.gateText.isEmpty ? snapshot.gateKind : snapshot.gateText
            return .blocked(detail.isEmpty ? "không rõ lý do" : detail)
        }
    }

    /// `data-retry-after` của nút thử lại: số giây, hoặc một mốc thời gian ISO 8601. Không đọc được ⇒ 0.
    static func retryAfterSeconds(_ raw: String, now: Date = Date()) -> Int {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return 0 }
        if let seconds = Double(value) { return max(0, Int(seconds.rounded(.up))) }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return max(0, Int(date.timeIntervalSince(now).rounded(.up))) }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return max(0, Int(date.timeIntervalSince(now).rounded(.up))) }
        return 0
    }

    /// Chỉ host + path cho log.
    static func describe(_ url: URL?) -> String {
        guard let url else { return "-" }
        return "\(url.host ?? "-")\(url.path)"
    }

    // MARK: - Câu trả lời

    static func cleanAnswer(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Phần phát dần trong lúc trang còn đang viết: chỉ các dòng đã trọn (đến dấu xuống dòng cuối), bỏ khoảng trắng ở
    /// **cuối** để bản cuối (`cleanAnswer`) luôn nối tiếp phần đã phát.
    static func streamablePrefix(_ raw: String) -> String {
        guard let lastBreak = raw.lastIndex(of: "\n") else { return "" }
        var prefix = raw[..<lastBreak]
        while let last = prefix.last, last.isWhitespace {
            prefix.removeLast()
        }
        return String(prefix)
    }
}
