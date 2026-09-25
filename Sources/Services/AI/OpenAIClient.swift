import Foundation

/// Client HTTP giao tiếp với bất kỳ API nào tương thích chuẩn OpenAI.
public actor OpenAIClient {
    public static let shared = OpenAIClient()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Lấy danh sách ID các Model có sẵn từ endpoint `GET /models`.
    public func fetchAvailableModels(baseURL: String, apiKey: String) async throws -> [String] {
        let cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: cleanBase) else {
            throw URLError(.badURL)
        }

        // Đảm bảo đường dẫn trỏ tới /models
        if !url.path.hasSuffix("/models") {
            if cleanBase.hasSuffix("/") {
                url = URL(string: cleanBase + "models") ?? url
            } else {
                url = URL(string: cleanBase + "/models") ?? url
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "OpenAIClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi kết nối API: HTTP \(status)"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var results: [String] = []
        // Định dạng OpenAI chuẩn: {"data": [{"id": "..."}, ...]}
        if let dataArray = json["data"] as? [[String: Any]] {
            for item in dataArray {
                if let id = item["id"] as? String, !id.isEmpty {
                    results.append(id)
                }
            }
        } else if let modelsArray = json["models"] as? [[String: Any]] {
            // Định dạng Google / Ollama
            for item in modelsArray {
                if let name = item["name"] as? String, !name.isEmpty {
                    results.append(name.replacingOccurrences(of: "models/", with: ""))
                }
            }
        }

        return results.sorted()
    }

    /// Gửi tin nhắn và nhận phản hồi dạng Streaming SSE thời gian thực.
    public func sendChatStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message]
    ) -> AsyncThrowingStream<String, Error> {
        if config.activeProfile.authType == "web" {
            return ChatGPTWebClient.shared.sendChatStreaming(
                model: config.activeProfile.selectedModel,
                messages: messages
            )
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let cleanBase = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    var endpointStr = cleanBase
                    if !endpointStr.hasSuffix("/chat/completions") {
                        endpointStr = endpointStr.hasSuffix("/") ? "\(endpointStr)chat/completions" : "\(endpointStr)/chat/completions"
                    }

                    guard let url = URL(string: endpointStr) else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 60
                    var effectiveToken = config.apiKey
                    if config.activeProfile.authType == "oauth" {
                        if let validToken = try? await OpenAIOAuthManager.shared.getValidAccessToken(for: config.activeProfile) {
                            effectiveToken = validToken
                        }
                    }
                    if !effectiveToken.isEmpty {
                        request.setValue("Bearer \(effectiveToken)", forHTTPHeaderField: "Authorization")
                    }

                    let payload = OpenAIChatRequest(
                        model: config.selectedModel,
                        messages: messages,
                        temperature: config.temperature,
                        stream: true
                    )
                    request.httpBody = try JSONEncoder().encode(payload)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: NSError(domain: "OpenAIClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi API HTTP \(status)"]))
                        return
                    }

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let dataContent = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                        if dataContent == "[DONE]" {
                            break
                        }
                        guard let chunkData = dataContent.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let firstChoice = choices.first,
                              let delta = firstChoice["delta"] as? [String: Any],
                              let text = delta["content"] as? String, !text.isEmpty else {
                            continue
                        }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Gửi tin nhắn một lần (Non-streaming), hỗ trợ Function / Tool Calling.
    public func sendChat(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        tools: [OpenAIChatRequest.Tool]? = nil
    ) async throws -> (content: String?, toolCalls: [OpenAIChatRequest.ToolCall]?) {
        if config.activeProfile.authType == "web" {
            let text = try await ChatGPTWebClient.shared.sendChat(
                model: config.activeProfile.selectedModel,
                messages: messages
            )
            return (content: text, toolCalls: nil)
        }

        let cleanBase = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var endpointStr = cleanBase
        if !endpointStr.hasSuffix("/chat/completions") {
            endpointStr = endpointStr.hasSuffix("/") ? "\(endpointStr)chat/completions" : "\(endpointStr)/chat/completions"
        }

        guard let url = URL(string: endpointStr) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        var effectiveToken = config.apiKey
        if config.activeProfile.authType == "oauth" {
            if let validToken = try? await OpenAIOAuthManager.shared.getValidAccessToken(for: config.activeProfile) {
                effectiveToken = validToken
            }
        }
        if !effectiveToken.isEmpty {
            request.setValue("Bearer \(effectiveToken)", forHTTPHeaderField: "Authorization")
        }

        let payload = OpenAIChatRequest(
            model: config.selectedModel,
            messages: messages,
            temperature: config.temperature,
            stream: false,
            tools: tools
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyMsg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAIClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi HTTP \(status): \(bodyMsg)"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            return (nil, nil)
        }

        let content = message["content"] as? String
        var toolCalls: [OpenAIChatRequest.ToolCall]? = nil

        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            var parsedCalls: [OpenAIChatRequest.ToolCall] = []
            for item in rawCalls {
                if let funcDict = item["function"] as? [String: Any],
                   let name = funcDict["name"] as? String,
                   let args = funcDict["arguments"] as? String {
                    let call = OpenAIChatRequest.ToolCall(
                        id: item["id"] as? String,
                        type: item["type"] as? String,
                        function: OpenAIChatRequest.ToolCall.FunctionCall(name: name, arguments: args)
                    )
                    parsedCalls.append(call)
                }
            }
            if !parsedCalls.isEmpty {
                toolCalls = parsedCalls
            }
        }

        return (content, toolCalls)
    }
}
