import Foundation

/// Dựng URL, header và body form cho hai endpoint web của Gemini. Thuần — không mạng, không WebKit.
///
/// Cấu trúc mảng 81 ô của `f.req` chép theo `gemini-webapi` (Python) bản 2026-10; các ô không liệt
/// kê giữ `null`. Đổi một ô ở đây phải đối chiếu lại với thư viện đó — không có tài liệu chính thức
/// nào cho giao thức này. Ô `[45] = 1` là **temporary chat**: lượt chat không lưu vào lịch sử Gemini
/// của tài khoản, vì app gửi lại toàn bộ ngữ cảnh ở mỗi lượt (xem `GeminiWebPromptFormatter`).
enum GeminiWebRequestBuilder {
    static let origin = "https://gemini.google.com"
    static let appURL = URL(string: "https://gemini.google.com/app")!
    /// Đăng nhập xong Google chuyển thẳng về `/app` — `GeminiWebLoginLauncher` dựa vào host đích để tự đóng tab.
    static let loginURL = URL(string: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fgemini.google.com%2Fapp&hl=vi")!
    static let generateEndpoint = "https://gemini.google.com/_/BardChatUi/data/assistant.lamda.BardFrontendService/StreamGenerate"
    static let batchExecuteEndpoint = "https://gemini.google.com/_/BardChatUi/data/batchexecute"
    /// RPC `GetUserStatus`: trạng thái tài khoản + danh sách model.
    static let userStatusRPC = "otAQ7b"

    /// Một request đã sẵn sàng để `fetch()` trong trang; `fields` là body `application/x-www-form-urlencoded`.
    struct Request: Sendable, Equatable {
        let url: String
        let headers: [String: String]
        let fields: [String: String]
    }

    private static let commonHeaders: [String: String] = [
        "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        "X-Same-Domain": "1"
    ]

    // MARK: - StreamGenerate

    static func generate(
        prompt: String,
        session: GeminiWebInitSession,
        model: GeminiWebModel?,
        requestId: Int
    ) throws -> Request {
        let requestUUID = UUID().uuidString.uppercased()
        let inner = innerRequestArray(
            prompt: prompt,
            language: session.language,
            requestUUID: requestUUID,
            modelNumber: model?.modelNumber
        )
        let innerJSON = try jsonString(inner)
        let outerJSON = try jsonString([NSNull(), innerJSON] as [Any])

        var headers = commonHeaders
        headers["x-goog-ext-525005358-jspb"] = "[\"\(requestUUID)\",1]"
        headers["x-goog-ext-73010989-jspb"] = "[0]"
        headers["x-goog-ext-73010990-jspb"] = "[0,0,0]"
        if let model {
            headers[GeminiWebModel.headerKey] = model.headerValue(sessionUUID: session.sessionUUID)
        }

        let url = try buildURL(generateEndpoint, query: baseQuery(session: session, requestId: requestId))
        return Request(url: url, headers: headers, fields: ["at": session.accessToken, "f.req": outerJSON])
    }

    /// Mảng 81 ô của một lượt sinh nội dung (không file đính kèm, không gem, không deep research).
    static func innerRequestArray(prompt: String, language: String, requestUUID: String, modelNumber: Int?) -> [Any] {
        var slots: [Any] = Array(repeating: NSNull(), count: 81)
        slots[0] = [prompt, 0, NSNull(), NSNull(), NSNull(), NSNull(), 0] as [Any]
        slots[1] = [language]
        // Metadata hội thoại rỗng = bắt đầu hội thoại mới (không cid/rid/rcid).
        slots[2] = ["", "", "", NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), ""] as [Any]
        slots[6] = [1]
        slots[7] = 1   // streaming
        slots[10] = 1
        slots[11] = 0
        slots[17] = [[0]]
        slots[18] = 0
        slots[27] = 1
        slots[30] = [4]
        slots[41] = [1]
        slots[45] = 1  // temporary chat
        slots[53] = 0
        slots[59] = requestUUID
        slots[61] = [Any]()
        slots[68] = 1
        slots[79] = modelNumber ?? 1
        slots[80] = 1  // 1 = không extended thinking
        return slots
    }

    // MARK: - batchexecute

    static func userStatus(session: GeminiWebInitSession, requestId: Int) throws -> Request {
        let payload = try jsonString([[[userStatusRPC, "[]", NSNull(), "generic"] as [Any]]])
        var headers = commonHeaders
        headers[GeminiWebModel.headerKey] = GeminiWebModel.batchHeaderValue(sessionUUID: session.sessionUUID)
        headers["x-goog-ext-73010989-jspb"] = "[0]"

        var query = baseQuery(session: session, requestId: requestId)
        query.insert(URLQueryItem(name: "rpcids", value: userStatusRPC), at: 0)
        query.append(URLQueryItem(name: "source-path", value: "/app"))
        let url = try buildURL(batchExecuteEndpoint, query: query)
        return Request(url: url, headers: headers, fields: ["at": session.accessToken, "f.req": payload])
    }

    // MARK: - Phụ trợ

    private static func baseQuery(session: GeminiWebInitSession, requestId: Int) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "hl", value: session.language),
            URLQueryItem(name: "_reqid", value: String(requestId)),
            URLQueryItem(name: "rt", value: "c")
        ]
        if let buildLabel = session.buildLabel, !buildLabel.isEmpty {
            items.append(URLQueryItem(name: "bl", value: buildLabel))
        }
        if let sessionId = session.sessionId, !sessionId.isEmpty {
            items.append(URLQueryItem(name: "f.sid", value: sessionId))
        }
        return items
    }

    private static func buildURL(_ endpoint: String, query: [URLQueryItem]) throws -> String {
        guard var components = URLComponents(string: endpoint) else {
            throw GeminiWebError.protocolChanged("endpoint không hợp lệ: \(endpoint)")
        }
        components.queryItems = query
        guard let url = components.url?.absoluteString else {
            throw GeminiWebError.protocolChanged("không dựng được URL cho \(endpoint)")
        }
        return url
    }

    static func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw GeminiWebError.protocolChanged("không mã hoá được request sang JSON")
        }
        return text
    }
}
