import Foundation

/// Lỗi của engine nguồn Legado, có phân loại để bộ chạy nghiệm thu đếm (spec §7.2).
/// `CancellationError` **không** bao giờ bị bọc thành lỗi này.
enum LegadoEngineError: LocalizedError {
    enum Category: String {
        /// Cú pháp/hàm/tính năng chưa hỗ trợ ở bản này (stub JS, URL `data:`…).
        case unsupportedSyntax
        case http
        case timeout
        case network
        case javaScript
        /// Rule chạy được nhưng khớp 0 (do luồng xác định).
        case noMatch
        case invalidSource
    }

    case unsupportedSyntax(String)
    case httpStatus(code: Int, url: String, body: String)
    case timeout(url: String)
    case network(url: String, message: String)
    case javaScript(String)
    case noMatch(String)
    /// Ghép URL tương đối nhưng nguồn không có URL gốc (`bookSourceUrl` không phải URL, §1.4).
    case missingBaseURL(String)
    case invalidURL(String)

    var category: Category {
        switch self {
        case .unsupportedSyntax: return .unsupportedSyntax
        case .httpStatus: return .http
        case .timeout: return .timeout
        case .network: return .network
        case .javaScript: return .javaScript
        case .noMatch: return .noMatch
        case .missingBaseURL, .invalidURL: return .invalidSource
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedSyntax(let what):
            return "Chưa hỗ trợ \(what) ở bản này"
        case .httpStatus(let code, let url, _):
            return "HTTP \(code) khi tải \(url)"
        case .timeout(let url):
            return "Quá thời gian chờ khi tải \(url)"
        case .network(let url, let message):
            return "Lỗi mạng khi tải \(url): \(message)"
        case .javaScript(let message):
            return "Lỗi JS: \(message)"
        case .noMatch(let what):
            return "Rule không khớp: \(what)"
        case .missingBaseURL(let url):
            return "Nguồn không có URL gốc để ghép \(url)"
        case .invalidURL(let url):
            return "URL không hợp lệ: \(url)"
        }
    }
}
