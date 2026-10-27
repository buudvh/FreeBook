import Foundation

/// Trang web đã gây lỗi tải nội dung từ nguồn — đích của nút "Mở link lỗi" (`ErrorLinkButton`, `.errorLinkBrowser`).
///
/// Cách dùng ở một màn (giữ state chữ lỗi `String` như cũ, thêm state link gán **cùng chỗ** gán lỗi):
/// ```swift
/// @State private var errorLink: SourceErrorLink?        // link của lỗi đang hiện (dòng URL xám + nút)
/// @State private var openingErrorLink: SourceErrorLink? // đang mở trình duyệt
/// } catch {
///     errorMessage = error.localizedDescription
///     errorLink = SourceErrorLink.resolve(from: error, fallback: chapterUrl, host: bookHost)
/// }
/// ```
///
/// Thứ tự chọn URL (`resolve`): `fetch` lỗi thật của lượt chạy script (`ExtensionLoadError.failedFetchURL`) → `fetch`
/// gần nhất kể cả 200 (`lastFetchURL`) → URL request lỗi của engine Legado (`LegadoEngineError` http/timeout/network) →
/// lần lượt từng URL dự phòng (URL đầu vào của màn: chương, chi tiết, thể loại, trang chủ nguồn). Không ứng viên nào
/// hợp lệ ⇒ `nil` (màn ẩn nút).
///
/// Hợp lệ = `http(s)` tuyệt đối có host, không chứa `{`/`}` (mẫu kiểu `{0}`). URL dự phòng được bỏ khối option Legado
/// `,{…}` rồi chuẩn hoá như lúc gọi script (`ExtensionURLFormatter.cleanAndResolve`); đường dẫn tương đối chỉ nhận
/// dạng bắt đầu bằng `/` (ghép theo `host`) — chữ trần như từ khoá thể loại không bao giờ thành URL.
///
/// URL có thể mang query chứa token: hiển thị chỉ dùng `displayText` (host + path), **không** log `url`.
struct SourceErrorLink: Equatable, Hashable, Identifiable, Sendable {
    enum Origin: String, Sendable {
        /// `fetch` lỗi thật của lượt chạy script, hoặc URL request lỗi của engine Legado.
        case failedFetch
        /// `fetch` gần nhất của lượt chạy (kể cả 200) — lỗi script/parse sau một fetch thành công.
        case lastFetch
        /// URL đầu vào của màn (dự phòng).
        case input
    }

    /// URL tuyệt đối đã kiểm (`http(s)`, có host, đã percent-encode) — mở nguyên văn trong trình duyệt.
    let url: String
    let origin: Origin

    /// Cho `fullScreenCover(item:)`.
    var id: String { url }

    /// Host để chép cookie sau khi đóng trình duyệt (`WebKitCookieBridge`).
    var host: String? { URL(string: url)?.host }

    /// Dòng URL xám dưới câu lỗi: `host + path`, **không** query/fragment (có thể chứa token).
    var displayText: String {
        guard let parsed = URL(string: url), let host = parsed.host else { return url }
        let path = parsed.path
        return path.isEmpty || path == "/" ? host : host + path
    }

    /// Dựng trực tiếp từ một URL đã biết (không qua lỗi); URL không hợp lệ ⇒ `nil`. `host` chỉ dùng cho `.input` để
    /// ghép đường dẫn tương đối.
    init?(url rawURL: String?, origin: Origin, host: String? = nil) {
        let candidate = origin == .input ? Self.normalizedInput(rawURL, host: host) : Self.validated(rawURL)
        guard let candidate else { return nil }
        self.url = candidate
        self.origin = origin
    }

    /// Link cho một lỗi tải nội dung, với một URL dự phòng (URL đầu vào của màn). Xem thứ tự ở doc của type.
    static func resolve(from error: Error?, fallback: String?, host: String? = nil) -> SourceErrorLink? {
        resolve(from: error, fallbacks: [fallback], host: host)
    }

    /// Như `resolve(from:fallback:host:)` nhưng thử lần lượt nhiều URL dự phòng (vd `category.input` rồi `sourceUrl`).
    static func resolve(from error: Error?, fallbacks: [String?], host: String? = nil) -> SourceErrorLink? {
        if let error {
            if let wrapped = error as? ExtensionLoadError {
                if let link = SourceErrorLink(url: wrapped.failedFetchURL, origin: .failedFetch) { return link }
                if let link = SourceErrorLink(url: wrapped.lastFetchURL, origin: .lastFetch) { return link }
            }
            if let engineURL = legadoRequestURL(of: ExtensionLoadError.unwrapped(error)),
               let link = SourceErrorLink(url: engineURL, origin: .failedFetch) {
                return link
            }
        }
        for fallback in fallbacks {
            if let link = SourceErrorLink(url: fallback, origin: .input, host: host) { return link }
        }
        return nil
    }

    // MARK: - Kiểm & chuẩn hoá

    /// URL request của lỗi mạng engine Legado; lỗi khác ⇒ `nil`.
    private static func legadoRequestURL(of error: Error) -> String? {
        guard let engineError = error as? LegadoEngineError else { return nil }
        switch engineError {
        case .httpStatus(_, let url, _), .timeout(let url), .network(let url, _):
            return url
        default:
            return nil
        }
    }

    /// URL dự phòng: bỏ khối option Legado, chỉ nhận `http(s)://…`, `//…`, `/…` rồi chuẩn hoá như lúc gọi script.
    private static func normalizedInput(_ raw: String?, host: String?) -> String? {
        guard let raw else { return nil }
        let candidate = LegadoURLResolver.splitOption(raw).url
        let lower = candidate.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || candidate.hasPrefix("/") else { return nil }
        return validated(ExtensionURLFormatter.cleanAndResolve(candidate, host: host))
    }

    /// `http(s)` tuyệt đối có host, không phải mẫu `{…}` ⇒ `absoluteString` (iOS 17 tự percent-encode ký tự lạ).
    private static func validated(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              !trimmed.contains("{"), !trimmed.contains("}"),
              let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parsed.host, !host.isEmpty else { return nil }
        return parsed.absoluteString
    }
}
