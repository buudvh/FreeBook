import Foundation

/// Client HTTP giao tiếp với bất kỳ API nào tương thích chuẩn OpenAI.
public actor OpenAIClient {
    public static let shared = OpenAIClient()

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

    /// Lấy danh sách ID các Model có sẵn từ endpoint `GET /models`, tự động đổi key nếu gặp lỗi 401/429/403.
    public func fetchAvailableModels(baseURL: String, apiKey: String, apiKeys: [String] = []) async throws -> [String] {
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

        var candidateKeys = apiKeys.map { cleanToken($0) }.filter { !$0.isEmpty }
        if candidateKeys.isEmpty {
            let single = cleanToken(apiKey)
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
            if !currentKey.isEmpty {
                request.setValue("Bearer \(currentKey)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let bodyMsg = String(data: data, encoding: .utf8) ?? ""
                    let err = NSError(domain: "OpenAIClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi kết nối API: HTTP \(status) (\(bodyMsg))"])

                    if (status == 401 || status == 403 || status == 429) && index < candidateKeys.count - 1 {
                        AppLogger.shared.log("⚠️ OpenAI fetchModels Key [\(index + 1)/\(candidateKeys.count)] lỗi HTTP \(status). Chuyển sang key kế tiếp...")
                        lastError = err
                        continue
                    }
                    throw err
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
            } catch {
                lastError = error
                if index < candidateKeys.count - 1 {
                    continue
                }
                throw error
            }
        }

        throw lastError ?? NSError(domain: "OpenAIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Toàn bộ API Key đều thất bại."])
    }

    /// Gửi tin nhắn và nhận phản hồi dạng Streaming SSE thời gian thực, tự động đổi key khi lỗi.
    public func sendChatStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message]
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                let cleanBase = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                var endpointStr = cleanBase
                if !endpointStr.hasSuffix("/chat/completions") {
                    endpointStr = endpointStr.hasSuffix("/") ? "\(endpointStr)chat/completions" : "\(endpointStr)/chat/completions"
                }

                guard let url = URL(string: endpointStr) else {
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
                        request.timeoutInterval = 60
                        let token = cleanToken(currentKey)
                        if !token.isEmpty {
                            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
                            var errorBody = ""
                            for try await line in bytes.lines {
                                errorBody += line
                                if errorBody.count > 1000 { break }
                            }
                            let err = NSError(domain: "OpenAIClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi API HTTP \(status) (\(errorBody))"])

                            if (status == 401 || status == 403 || status == 429) && index < candidateKeys.count - 1 {
                                AppLogger.shared.log("⚠️ OpenAI Streaming Key [\(index + 1)/\(candidateKeys.count)] lỗi HTTP \(status). Chuyển sang key kế tiếp...")
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
                        return
                    } catch {
                        lastError = error
                        if index < candidateKeys.count - 1 {
                            AppLogger.shared.log("⚠️ OpenAI Streaming Key [\(index + 1)/\(candidateKeys.count)] thất bại: \(error.localizedDescription). Thử key tiếp...")
                            continue
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish(throwing: lastError ?? NSError(domain: "OpenAIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Toàn bộ API Key đều thất bại."]))
            }
        }
    }

    /// Gửi tin nhắn một lần (Non-streaming), hỗ trợ Function / Tool Calling và tự động đổi key khi lỗi.
    public func sendChat(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        tools: [OpenAIChatRequest.Tool]? = nil
    ) async throws -> (content: String?, toolCalls: [OpenAIChatRequest.ToolCall]?) {
        let cleanBase = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var endpointStr = cleanBase
        if !endpointStr.hasSuffix("/chat/completions") {
            endpointStr = endpointStr.hasSuffix("/") ? "\(endpointStr)chat/completions" : "\(endpointStr)/chat/completions"
        }

        guard let url = URL(string: endpointStr) else {
            throw URLError(.badURL)
        }

        let keys = config.activeProfile.allEffectiveApiKeys()
        let candidateKeys = keys.isEmpty ? [config.apiKey] : keys

        var lastError: Error?
        for (index, currentKey) in candidateKeys.enumerated() {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 60
            let token = cleanToken(currentKey)
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let payload = OpenAIChatRequest(
                model: config.selectedModel,
                messages: messages,
                temperature: config.temperature,
                stream: false,
                tools: tools
            )
            request.httpBody = try JSONEncoder().encode(payload)

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let bodyMsg = String(data: data, encoding: .utf8) ?? ""
                    let err = NSError(domain: "OpenAIClient", code: status, userInfo: [NSLocalizedDescriptionKey: "Lỗi HTTP \(status): \(bodyMsg)"])

                    if (status == 401 || status == 403 || status == 429) && index < candidateKeys.count - 1 {
                        AppLogger.shared.log("⚠️ OpenAI Key [\(index + 1)/\(candidateKeys.count)] lỗi HTTP \(status). Chuyển sang key kế tiếp...")
                        lastError = err
                        continue
                    }
                    throw err
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
            } catch {
                lastError = error
                if index < candidateKeys.count - 1 {
                    AppLogger.shared.log("⚠️ OpenAI Key [\(index + 1)/\(candidateKeys.count)] thất bại: \(error.localizedDescription). Thử key tiếp...")
                    continue
                }
                throw error
            }
        }

        throw lastError ?? NSError(domain: "OpenAIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Toàn bộ danh sách API Key đều thất bại."])
    }

    /// Kiểm tra kết nối nhanh bằng cách gửi 1 prompt ngắn gọn và nhận phản hồi.
    public func testChatPing(config: AIConfiguration) async throws -> String {
        let pingMessage = OpenAIChatRequest.Message(role: "user", content: "Xin chào, phản hồi lại ngắn gọn: OK")
        let (content, _) = try await sendChat(config: config, messages: [pingMessage])
        guard let text = content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw NSError(domain: "OpenAIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "API không trả về nội dung tin nhắn."])
        }
        return text
    }
}
