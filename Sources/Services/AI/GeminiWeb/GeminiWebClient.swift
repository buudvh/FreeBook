import Foundation

/// Client Gemini Web — bề mặt giống `OpenAIClient`/`AnthropicClient` để các chỗ rẽ nhánh theo
/// `apiFormat` gọi được y hệt. Phần WebKit nằm ở `GeminiWebSessionController` (MainActor); actor
/// này chỉ dựng request, bóc frame và đổi text tích luỹ thành delta.
///
/// Phạm vi cố ý: **chỉ chat**. `AIContextCompactor` bỏ qua và `AINameExtractionBatchProcessor` từ
/// chối profile Gemini Web — gọi dồn dập là tài khoản bị 1037 (hết hạn mức) hoặc 1060 (chặn IP).
///
/// Retry thuộc về đúng tầng này: một lần khi 1013 (lỗi tạm) hoặc khi token cũ (HTTP 400/401/403 ⇒
/// nạp lại trang). `AIRuntimeCoordinator` không bọc thêm vòng retry.
public actor GeminiWebClient {
    public static let shared = GeminiWebClient()

    /// Giá trị `AIProviderProfile.apiFormat` của provider này.
    public static let apiFormat = "geminiWeb"
    /// Tên model gợi ý khi chưa khám phá được danh sách thật của tài khoản.
    public static let fallbackModelNames = ["gemini-flash", "gemini-pro", "gemini-flash-lite"]

    private static let modelCacheLifetime: TimeInterval = 6 * 3600

    private var models: [GeminiWebModel] = []
    private var modelsLoadedAt: Date?

    private init() {}

    // MARK: - Tài khoản

    public func isSignedIn() async -> Bool {
        await GeminiWebSessionController.shared.isSignedIn()
    }

    public func signOut() async {
        await GeminiWebSessionController.shared.signOut()
        models = []
        modelsLoadedAt = nil
    }

    /// Sau khi đăng nhập xong ở `GeminiWebLoginView`: ép lượt kế tiếp nạp lại trang để lấy token mới.
    public func refreshAfterLogin() async {
        await GeminiWebSessionController.shared.invalidateSession()
        models = []
        modelsLoadedAt = nil
    }

    // MARK: - API tương đương OpenAIClient

    /// Khám phá model của tài khoản qua `GetUserStatus`; trả tên dạng `gemini-flash` để lưu vào profile.
    public func fetchAvailableModels() async throws -> [String] {
        try await discoverModels(force: true).map(\.name)
    }

    public func sendChatStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message]
    ) -> AsyncThrowingStream<String, Error> {
        let prompt = GeminiWebPromptFormatter.buildPrompt(from: messages)
        let modelName = config.selectedModel
        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: GeminiWebError.sessionUnavailable)
                    return
                }
                do {
                    try await self.streamGeneration(prompt: prompt, modelName: modelName) { delta in
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func sendChat(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message]
    ) async throws -> (content: String?, toolCalls: [OpenAIChatRequest.ToolCall]?) {
        var text = ""
        for try await delta in sendChatStreaming(config: config, messages: messages) {
            text += delta
        }
        return (text.isEmpty ? nil : text, nil)
    }

    public func testChatPing(config: AIConfiguration) async throws -> String {
        let ping = OpenAIChatRequest.Message(role: "user", content: "Xin chào, phản hồi lại ngắn gọn: OK")
        let (content, _) = try await sendChat(config: config, messages: [ping])
        guard let text = content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw GeminiWebError.protocolChanged("Gemini không trả về nội dung")
        }
        return text
    }

    // MARK: - Lõi

    /// Một lượt sinh nội dung: nạp phiên → (khám phá model nếu chưa) → fetch → bóc frame → phát delta.
    private func streamGeneration(
        prompt: String,
        modelName: String,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        var session = try await GeminiWebSessionController.shared.prepare()
        let model = await resolveModel(named: modelName)
        var attempt = 0

        while true {
            try Task.checkCancellation()
            do {
                let requestId = await GeminiWebSessionController.shared.nextRequestId()
                let request = try GeminiWebRequestBuilder.generate(
                    prompt: prompt,
                    session: session,
                    model: model,
                    requestId: requestId
                )
                try await consumeGeneration(request: request, onDelta: onDelta)
                return
            } catch let error as GeminiWebError where attempt == 0 && (error.isRetryable || error.suggestsSessionRefresh) {
                attempt += 1
                AppLogger.shared.log("🤖 [GeminiWeb] Lượt 1 lỗi (\(error.localizedDescription)) — thử lại 1 lần\(error.suggestsSessionRefresh ? " sau khi nạp lại trang" : "")")
                if error.suggestsSessionRefresh {
                    session = try await GeminiWebSessionController.shared.prepare(force: true)
                } else {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    /// Frame của Gemini mang **text tích luỹ**; coordinator cộng dồn delta nên ở đây đổi sang delta
    /// theo tiền tố (so theo unicode scalar để chunk cắt giữa cụm ký tự không làm hỏng phép so).
    private func consumeGeneration(
        request: GeminiWebRequestBuilder.Request,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        let raw = await GeminiWebSessionController.shared.fetchStream(request)
        var parser = GeminiWebFrameParser()
        var emitted = ""
        var latest = ""
        var sawCandidate = false
        var rewrites = 0

        func handle(_ frames: [Any]) throws {
            for part in frames {
                guard let frame = try GeminiWebResponseParser.parseGenerateEnvelope(part) else { continue }
                sawCandidate = true
                latest = frame.text
                if frame.text.unicodeScalars.starts(with: emitted.unicodeScalars) {
                    let suffix = frame.text.unicodeScalars.dropFirst(emitted.unicodeScalars.count)
                    let delta = String(String.UnicodeScalarView(suffix))
                    if !delta.isEmpty {
                        onDelta(delta)
                        emitted = frame.text
                    }
                } else {
                    rewrites += 1
                }
            }
        }

        for try await chunk in raw {
            try Task.checkCancellation()
            try handle(parser.feed(chunk))
        }
        try handle(parser.flush())

        guard sawCandidate else {
            throw GeminiWebError.protocolChanged("phản hồi StreamGenerate không có ứng viên ([4][0][1][0])")
        }
        if latest != emitted {
            // Google thay cả câu trả lời (vd. bộ lọc an toàn): nối bản cuối vào sau phần đã hiện.
            onDelta("\n\n— Gemini sửa lại câu trả lời —\n\(latest)")
            AppLogger.shared.log("🤖 [GeminiWeb] Text bị viết lại \(rewrites) lần, đã nối bản cuối")
        }
    }

    // MARK: - Model

    /// Không khớp model nào ⇒ `nil` ⇒ gửi không kèm header model, Google tự chọn mặc định.
    private func resolveModel(named name: String) async -> GeminiWebModel? {
        if modelsExpired {
            do {
                _ = try await discoverModels(force: false)
            } catch {
                AppLogger.shared.log("🤖 [GeminiWeb] Không khám phá được model (\(error.localizedDescription)) — gửi không kèm header model")
            }
        }
        return models.first { $0.matches(name) }
    }

    private var modelsExpired: Bool {
        guard !models.isEmpty, let loadedAt = modelsLoadedAt else { return true }
        return Date().timeIntervalSince(loadedAt) > Self.modelCacheLifetime
    }

    private func discoverModels(force: Bool) async throws -> [GeminiWebModel] {
        if !force, !modelsExpired { return models }
        let session = try await GeminiWebSessionController.shared.prepare(force: force)
        let requestId = await GeminiWebSessionController.shared.nextRequestId()
        let request = try GeminiWebRequestBuilder.userStatus(session: session, requestId: requestId)

        let raw = await GeminiWebSessionController.shared.fetchStream(request, timeout: 30)
        var text = ""
        for try await chunk in raw {
            text += chunk
        }
        var parser = GeminiWebFrameParser()
        var frames = parser.feed(text)
        frames.append(contentsOf: parser.flush())

        let status = try GeminiWebResponseParser.parseUserStatus(envelopes: frames)
        if let failure = GeminiWebError.fromAccountStatus(status.statusCode) { throw failure }
        models = status.models
        modelsLoadedAt = Date()
        AppLogger.shared.log("🤖 [GeminiWeb] Khám phá \(models.count) model: \(models.map(\.name).joined(separator: ", "))")
        return models
    }
}
