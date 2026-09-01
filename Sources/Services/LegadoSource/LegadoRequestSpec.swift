import Foundation

/// Yêu cầu HTTP đã giải xong từ một rule URL của Legado.
public struct LegadoRequestSpec {
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let body: Data?
    /// Tên bảng mã do nguồn khai (`charset`), dùng cho **cả** encode query/body và decode phản hồi.
    public let charset: String?
    public let retry: Int
    public let requiresWebView: Bool

    public init(
        url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        charset: String? = nil,
        retry: Int = 0,
        requiresWebView: Bool = false
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.charset = charset
        self.retry = retry
        self.requiresWebView = requiresWebView
    }

    public var isPost: Bool {
        method.uppercased() == "POST"
    }
}
