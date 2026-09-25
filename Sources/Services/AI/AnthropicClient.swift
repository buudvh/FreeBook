import Foundation

/// Client HTTP giao tiếp trực tiếp với Anthropic Messages API (`/v1/messages`).
public actor AnthropicClient {
    public static let shared = AnthropicClient()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Chuẩn hoá đường dẫn endpoint cho Anthropic API.
    private func resolveEndpoint(baseURL: String, path: String) -> URL? {
        var cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBase.hasSuffix("/") {
            cleanBase = String(cleanBase.dropLast())
        }

        if path == "messages" {
            if cleanBase.hasSuffix("/messages") {
                return URL(string: cleanBase)
            }
            if cleanBase.hasSuffix("/v1") {
                return URL(string: "\(cleanBase)/messages")
            }
            return URL(string: "\(cleanBase)/v1/messages")
        } else if path == "models" {
            if cleanBase.hasSuffix("/messages") {
                let baseWithoutMessages = String(cleanBase.dropLast("/messages".count))
                return URL(string: "\(baseWithoutMessages)/models")
            }
            if cleanBase.hasSuffix("/v1") {
                return URL(string: "\(cleanBase)/models")
            }
            return URL(string: "\(cleanBase)/v1/models")
        }

        return URL(string: "\(cleanBase)/\(path)")
    }

    /// Lấy danh sách ID các Model có sẵn từ Anthropic `GET /models`, fallback danh sách mới nhất nếu không hỗ trợ.
    public func fetchAvailableModels(baseURL: String, apiKey: String) async throws -> [String] {
        let fallbackModels = [
            "claude-3-7-sonnet-latest",
            "claude-3-5-sonnet-latest",
            "claude-3-5-haiku-latest",
            "claude-3-7-sonnet-20250219",
            "claude-3-5-sonnet-20241022",
            "claude-3-opus-latest"
        ]

        guard let url = resolveEndpoint(baseURL: baseURL, path: "models") else {
            return fallbackModels
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "x-api-key")
        }
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return fallbackModels
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return fallbackModels
            }

            var results: [String] = []
            if let dataArray = json["data"] as? [[String: Any]] {
                for item in dataArray {
                    if let id = item["id"] as? String, !id.isEmpty {
                        results.append(id)
                    }
                }
            }

            return results.isEmpty ? fallbackModels : results.sorted()
        } catch {
            return fallbackModels
        }
    }

    /// Chuyển đổi và chuẩn hoá mảng OpenAIChatRequest.Message thành format hợp lệ của Anthropic Messages API.
    private func prepareAnthropicPayload(
        messages: [OpenAIChatRequest.Message],
        model: String,
        temperature: Double?,
        stream: Bool
    ) -> AnthropicMessageRequest {
        var systemChunks: [String] = []
        var anthropicMessages: [AnthropicMessageRequest.Message] = []

        for msg in messages {
            let text = msg.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if msg.role == "system" {
                if !text.isEmpty {
                    systemChunks.append(text)
                }
            } else {
                let role = (msg.role == "assistant") ? "assistant" : "user"
                if !text.isEmpty {
                    // Anthropic yêu cầu role luân phiên xen kẽ: nếu role trùng với message trước đó thì gộp nội dung
                    if let last = anthropicMessages.last, last.role == role {
                        let merged = last.content + "\n\n" + text
                        anthropicMessages[anthropicMessages.count - 1] = AnthropicMessageRequest.Message(role: role, content: merged)
                    } else {
                        anthropicMessages.append(AnthropicMessageRequest.Message(role: role, content: text))
                    }
                }
            }
        }

        // Nếu message đầu tiên là assistant, chèn placeholder user ở đầu để hợp lệ với schema Anthropic
        if let first = anthropicMessages.first, first.role != "user" {
            anthropicMessages.insert(AnthropicMessageRequest.Message(role: "user", content: "Tiếp tục."), at: 0)
        }

        let systemPrompt = systemChunks.isEmpty ? nil : systemChunks.joined(separator: "\n\n")

        return AnthropicMessageRequest(
            model: model,
            system: systemPrompt,
            messages: anthropicMessages,
            max_tokens: 4096,
            temperature: temperature,
            stream: stream
        )
    }

    /// Gửi tin nhắn và nhận phản hồi dạng Streaming SSE thời gian thực từ Anthropic API.
    public func sendChatStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message]
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = resolveEndpoint(baseURL: config.baseURL, path: "messages") else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.timeoutInterval = 60

                    let effectiveToken = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !effectiveToken.isEmpty {
                        request.setValue(effectiveToken, forHTTPHeaderField: "x-api-key")
                    }

                    let payload = prepareAnthropicPayload(
                        messages: messages,
                        model: config.selectedModel,
                        temperature: config.temperature,
                        stream: true
                    )
                    request.httpBody = try JSONEncoder().encode(payload)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: NSError(domain: "AnthropicClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi Anthropic API HTTP \(status)"]))
                        return
                    }

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let dataContent = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let chunkData = dataContent.data(using: .utf8),
                              let deltaObj = try? JSONDecoder().decode(AnthropicStreamDelta.self, from: chunkData),
                              let text = deltaObj.delta?.text, !text.isEmpty else {
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

    /// Gửi tin nhắn một lần (Non-streaming).
    public func sendChat(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message]
    ) async throws -> (content: String?, toolCalls: [OpenAIChatRequest.ToolCall]?) {
        guard let url = resolveEndpoint(baseURL: config.baseURL, path: "messages") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let effectiveToken = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effectiveToken.isEmpty {
            request.setValue(effectiveToken, forHTTPHeaderField: "x-api-key")
        }

        let payload = prepareAnthropicPayload(
            messages: messages,
            model: config.selectedModel,
            temperature: config.temperature,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "AnthropicClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi Anthropic API HTTP \(status)"])
        }

        let decoded = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
        let texts = decoded.content?.compactMap { $0.text } ?? []
        let combined = texts.joined()
        return (content: combined.isEmpty ? nil : combined, toolCalls: nil)
    }
}
