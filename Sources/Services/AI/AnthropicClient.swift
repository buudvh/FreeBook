import Foundation

/// Client HTTP giao tiếp trực tiếp với Anthropic Messages API (`/v1/messages`).
public actor AnthropicClient {
    public static let shared = AnthropicClient()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Làm sạch token: loại bỏ khoảng trắng, dấu nháy kép/đơn, và tiền tố 'Bearer ' nếu có.
    private func cleanToken(_ apiKey: String) -> String {
        var token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if (token.hasPrefix("\"") && token.hasSuffix("\"")) || (token.hasPrefix("'") && token.hasSuffix("'")) {
            token = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }

    /// Áp dụng Header xác thực theo tuỳ chọn (x-api-key hoặc Authorization: Bearer).
    private func applyAuthHeaders(to request: inout URLRequest, apiKey: String, authHeader: String) {
        let token = cleanToken(apiKey)
        guard !token.isEmpty else { return }
        if authHeader == "bearer" {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(token, forHTTPHeaderField: "x-api-key")
        }
    }

    /// Chuẩn hoá đường dẫn endpoint cho Anthropic API: không tự thêm /v1, người dùng tự cấu hình version trong base URL.
    private func resolveEndpoint(baseURL: String, path: String) -> URL? {
        var cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleanBase.hasSuffix("/") {
            cleanBase = String(cleanBase.dropLast())
        }

        if path == "messages" {
            if cleanBase.hasSuffix("/messages") {
                return URL(string: cleanBase)
            }
            return URL(string: "\(cleanBase)/messages")
        } else if path == "models" {
            if cleanBase.hasSuffix("/messages") {
                let baseWithoutMessages = String(cleanBase.dropLast("/messages".count))
                return URL(string: "\(baseWithoutMessages)/models")
            }
            if cleanBase.hasSuffix("/models") {
                return URL(string: cleanBase)
            }
            return URL(string: "\(cleanBase)/models")
        }

        return URL(string: "\(cleanBase)/\(path)")
    }

    /// Lấy danh sách ID các Model có sẵn từ Anthropic `GET /models`. Ném lỗi chi tiết nếu kết nối thất bại, tự động đổi key kế tiếp nếu gặp lỗi 401/429/403.
    public func fetchAvailableModels(baseURL: String, apiKey: String, apiKeys: [String] = [], authHeader: String = "bearer") async throws -> [String] {
        guard let url = resolveEndpoint(baseURL: baseURL, path: "models") else {
            throw URLError(.badURL)
        }

        var candidateKeys = apiKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if candidateKeys.isEmpty {
            let single = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !single.isEmpty { candidateKeys = [single] }
        }
        if candidateKeys.isEmpty {
            candidateKeys = [""]
        }

        var lastError: Error?
        for (index, currentKey) in candidateKeys.enumerated() {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            applyAuthHeaders(to: &request, apiKey: currentKey, authHeader: authHeader)
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let bodyMsg = String(data: data, encoding: .utf8) ?? ""
                    let detail = bodyMsg.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(bodyMsg)"
                    let err = NSError(domain: "AnthropicClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi tải models Anthropic (\(detail))"])
                    if (status == 401 || status == 403 || status == 429) && index < candidateKeys.count - 1 {
                        AppLogger.shared.log("⚠️ Anthropic fetchModels Key [\(index + 1)/\(candidateKeys.count)] lỗi HTTP \(status). Chuyển sang key kế tiếp...")
                        lastError = err
                        continue
                    }
                    throw err
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw NSError(domain: "AnthropicClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Dữ liệu trả về không phải JSON hợp lệ."])
                }

                var results: [String] = []
                if let dataArray = json["data"] as? [[String: Any]] {
                    for item in dataArray {
                        if let id = item["id"] as? String, !id.isEmpty {
                            results.append(id)
                        }
                    }
                }
                return results.sorted()
            } catch {
                lastError = error
                if index < candidateKeys.count - 1 {
                    continue
                }
                throw error
            }
        }
        throw lastError ?? NSError(domain: "AnthropicClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Toàn bộ API Key đều thất bại."])
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

    /// Gửi tin nhắn và nhận phản hồi dạng Streaming SSE thời gian thực từ Anthropic API, tự động đổi key khi lỗi.
    public func sendChatStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message]
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let url = resolveEndpoint(baseURL: config.baseURL, path: "messages") else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }

                let keys = config.activeProfile.allEffectiveApiKeys()
                let candidateKeys = keys.isEmpty ? [config.apiKey] : keys

                var lastError: Error?
                for (index, currentKey) in candidateKeys.enumerated() {
                    do {
                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                        request.timeoutInterval = 60
                        applyAuthHeaders(to: &request, apiKey: currentKey, authHeader: config.activeProfile.anthropicAuthHeader)

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
                            var errorBody = ""
                            for try await line in bytes.lines {
                                errorBody += line
                                if errorBody.count > 1000 { break }
                            }
                            let detail = errorBody.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(errorBody)"
                            let err = NSError(domain: "AnthropicClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi Anthropic API (\(detail))"])

                            if (status == 401 || status == 403 || status == 429) && index < candidateKeys.count - 1 {
                                AppLogger.shared.log("⚠️ Anthropic Streaming Key [\(index + 1)/\(candidateKeys.count)] lỗi HTTP \(status). Chuyển sang key kế tiếp...")
                                lastError = err
                                continue
                            }
                            continuation.finish(throwing: err)
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
                        return
                    } catch {
                        lastError = error
                        if index < candidateKeys.count - 1 {
                            AppLogger.shared.log("⚠️ Anthropic Streaming Key [\(index + 1)/\(candidateKeys.count)] thất bại: \(error.localizedDescription). Thử key tiếp...")
                            continue
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish(throwing: lastError ?? NSError(domain: "AnthropicClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Toàn bộ API Key đều thất bại."]))
            }
        }
    }

    /// Gửi tin nhắn một lần (Non-streaming), tự động đổi sang key tiếp theo nếu gặp lỗi 401/403/429.
    public func sendChat(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message]
    ) async throws -> (content: String?, toolCalls: [OpenAIChatRequest.ToolCall]?) {
        guard let url = resolveEndpoint(baseURL: config.baseURL, path: "messages") else {
            throw URLError(.badURL)
        }

        let keys = config.activeProfile.allEffectiveApiKeys()
        let candidateKeys = keys.isEmpty ? [config.apiKey] : keys

        var lastError: Error?
        for (index, currentKey) in candidateKeys.enumerated() {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.timeoutInterval = 60
            applyAuthHeaders(to: &request, apiKey: currentKey, authHeader: config.activeProfile.anthropicAuthHeader)

            let payload = prepareAnthropicPayload(
                messages: messages,
                model: config.selectedModel,
                temperature: config.temperature,
                stream: false
            )
            request.httpBody = try JSONEncoder().encode(payload)

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let bodyMsg = String(data: data, encoding: .utf8) ?? ""
                    let detail = bodyMsg.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(bodyMsg)"
                    let err = NSError(domain: "AnthropicClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi Anthropic API (\(detail))"])

                    if (status == 401 || status == 403 || status == 429) && index < candidateKeys.count - 1 {
                        AppLogger.shared.log("⚠️ Anthropic Key [\(index + 1)/\(candidateKeys.count)] lỗi HTTP \(status). Chuyển sang key kế tiếp...")
                        lastError = err
                        continue
                    }
                    throw err
                }

                let decoded = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
                let texts = decoded.content?.compactMap { $0.text } ?? []
                let combined = texts.joined()
                return (content: combined.isEmpty ? nil : combined, toolCalls: nil)
            } catch {
                lastError = error
                if index < candidateKeys.count - 1 {
                    AppLogger.shared.log("⚠️ Anthropic Key [\(index + 1)/\(candidateKeys.count)] thất bại: \(error.localizedDescription). Thử key tiếp theo...")
                    continue
                }
                throw error
            }
        }

        throw lastError ?? NSError(domain: "AnthropicClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Toàn bộ danh sách API Key đều thất bại."])
    }

    /// Kiểm tra kết nối nhanh bằng cách gửi 1 prompt ngắn gọn và nhận phản hồi.
    public func testChatPing(config: AIConfiguration) async throws -> String {
        let pingMessage = OpenAIChatRequest.Message(role: "user", content: "Xin chào, phản hồi lại ngắn gọn: OK")
        let (content, _) = try await sendChat(config: config, messages: [pingMessage])
        guard let text = content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw NSError(domain: "AnthropicClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "API không trả về nội dung tin nhắn."])
        }
        return text
    }
}
