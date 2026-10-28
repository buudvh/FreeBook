import Foundation

/// Kết luận "lỗi do ai" cho **một script lỗi** của Kiểm tra tiện ích JS.
///
/// Heuristic theo dấu hiệu chắc chắn — tiện ích JS không có run log như engine Legado (`LegadoFailureArbiter`):
/// - chữ captcha / Cloudflare / xác minh / đăng nhập, hoặc HTTP 401 ⇒ cần người dùng;
/// - lỗi mạng, hết giờ, HTTP, hoặc có `fetch` lỗi trong lượt chạy (`ExtensionLoadError.failedFetchURL`) ⇒ web;
/// - chạy xong mà trả rỗng ⇒ nguồn lỗi thời;
/// - thiếu file, sai cú pháp, ngoại lệ JS (`TypeError`, `ReferenceError`…) ⇒ lỗi script;
/// - còn lại (script tự báo `Response.error` mà không có fetch lỗi…) ⇒ chưa rõ.
///
/// `rawValue` đi vào JSON chia sẻ.
enum ExtensionCheckVerdict: String, Encodable, Sendable, CaseIterable {
    case web
    case needsUser
    case sourceOutdated
    case script
    case unknown

    var label: String {
        switch self {
        case .web: return "Web chặn / sập"
        case .needsUser: return "Cần xác minh / đăng nhập"
        case .sourceOutdated: return "Nguồn lỗi thời"
        case .script: return "Lỗi script"
        case .unknown: return "Chưa rõ"
        }
    }

    private static let userMarkers = ["captcha", "cloudflare", "just a moment", "xác minh", "đăng nhập", "login", "verify"]
    private static let scriptMarkers = [
        "typeerror", "referenceerror", "syntaxerror", "rangeerror", "js compile error",
        "is not a function", "undefined is not", "null is not"
    ]

    /// `error` là lỗi gốc (còn bọc `ExtensionLoadError` nếu có); `classification` tính trên lỗi đã gỡ bọc.
    static func judge(error: Error, classification: LegadoCorpusErrorClassifier.Classification) -> ExtensionCheckVerdict {
        let text = classification.message.lowercased()
        if userMarkers.contains(where: { text.contains($0) }) || classification.httpStatus == 401 {
            return .needsUser
        }
        switch classification.failureClass {
        case .http, .network, .timeout:
            return .web
        case .noMatch:
            return .sourceOutdated
        case .invalidSource, .javaScript, .unsupportedSyntax:
            return .script
        case .other:
            break
        }
        if scriptMarkers.contains(where: { text.contains($0) }) {
            return .script
        }
        if let wrapped = error as? ExtensionLoadError, wrapped.failedFetchURL != nil {
            return .web
        }
        return .unknown
    }
}
