import Foundation

/// Phản hồi HTTP đã giải mã cho engine Legado.
public struct LegadoHTTPResponse {
    public let statusCode: Int
    public let body: String
    public let rawData: Data
    public let headers: [String: String]
    /// URL cuối cùng sau redirect — dùng làm `baseUrl` để resolve link tương đối.
    public let finalUrl: String

    public init(
        statusCode: Int,
        body: String,
        rawData: Data,
        headers: [String: String],
        finalUrl: String
    ) {
        self.statusCode = statusCode
        self.body = body
        self.rawData = rawData
        self.headers = headers
        self.finalUrl = finalUrl
    }

    public var isSuccess: Bool {
        (200..<400).contains(statusCode)
    }

    /// Phản hồi có phải JSON — quyết định chế độ mặc định của rule (`isJSON` trong `AnalyzeRule`).
    public var looksLikeJSON: Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    public var jsonObject: Any? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
