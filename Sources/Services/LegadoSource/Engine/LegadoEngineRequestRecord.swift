import Foundation

/// Vết một request của phiên engine (HTTP, WebView hoặc URL `data:`), cho màn Gỡ lỗi từng bước. Chỉ giữ trong bộ nhớ
/// của phiên (`LegadoEngineDiagnostics.requests`), **không** ghi `AppLogger`.
struct LegadoEngineRequestRecord: Sendable {
    let method: String
    let url: String            // URL đã gửi (chỉ giữ trong bộ nhớ của phiên)
    let finalUrl: String       // sau chuyển hướng
    let statusCode: Int?       // nil khi lỗi mạng
    let charset: String?
    let byteCount: Int
    let durationMs: Int
    let viaWebView: Bool
    let bodySnippet: String    // tối đa 4 KB đầu của thân đã giải mã
    let errorMessage: String?

    /// Giới hạn byte UTF-8 của `bodySnippet`.
    static let snippetByteLimit = 4096

    /// Cắt `text` còn tối đa `snippetByteLimit` byte UTF-8, không cắt giữa ký tự.
    static func snippet(_ text: String) -> String {
        guard text.utf8.count > snippetByteLimit else { return text }
        var output = ""
        var used = 0
        for character in text {
            let size = String(character).utf8.count
            if used + size > snippetByteLimit { break }
            output.append(character)
            used += size
        }
        return output
    }
}
