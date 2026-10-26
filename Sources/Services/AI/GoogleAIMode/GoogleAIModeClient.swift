import Foundation

/// Client Chế độ AI của Google (`google.com/search?udm=50`, 1.3.609) — bề mặt giống `GeminiWebClient` để các chỗ rẽ
/// nhánh theo `apiFormat` gọi được y hệt.
///
/// Không có API: app mở trang Chế độ AI trong WKWebView ẩn (`GoogleAIModeSessionController`) và **đọc DOM**
/// (`GoogleAIModePageContract`). Mọi lượt đi qua một hàng đợi tuần tự (`GoogleAIModeTurnQueue`).
/// - Chat trong Reader (`sendConversationStreaming`): mỗi phiên chat của app nối tiếp **một** cuộc chat Chế độ AI —
///   `+Conversation.swift`.
/// - Quét tên riêng (`sendNameScanTurn`): mỗi lượt là một cuộc chat **mới**, tạm dừng khi app ở nền.
/// - Không model, không temperature, không tool calling; không dịch mượt (Chế độ AI chỉ tóm lược — đã thử).
///
/// Retry thuộc về đúng tầng này (`+Turn.swift`): một lần, chỉ khi chưa phát chữ nào. `AIRuntimeCoordinator` và
/// `AINameExtractionBatchProcessor` không bọc thêm vòng retry.
public actor GoogleAIModeClient {
    public static let shared = GoogleAIModeClient()

    /// Giá trị `AIProviderProfile.apiFormat` của provider này.
    public static let apiFormat = "googleAIMode"

    struct Timeouts: Sendable {
        /// Không có thay đổi nào trên trang (lượt mới, chữ mới) trong khoảng này ⇒ `.timeout`.
        let idle: TimeInterval
        let absolute: TimeInterval
    }

    static let chatTimeouts = Timeouts(idle: 45, absolute: 180)
    static let scanTimeouts = Timeouts(idle: 90, absolute: 240)

    private init() {}

    /// Cookie `__Secure-1PSID` của kho mặc định — chung với Gemini Web.
    public func isSignedIn() async -> Bool {
        await GeminiWebSessionController.shared.isSignedIn()
    }

    /// Chat trong Reader. `config` giữ cho giống chữ ký các client khác (không có model để chọn).
    public func sendConversationStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        sessionId: UUID
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: GoogleAIModeError.webViewUnavailable)
                    return
                }
                do {
                    try await self.runConversation(messages: messages, sessionId: sessionId) { delta in
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

    /// Một lượt quét tên riêng: cuộc chat mới, prompt không được cắt (chỉ dẫn trích xuất phải đủ), tạm dừng khi app ở
    /// nền. Lỗi làm dừng cả lần quét: `GoogleAIModeError.stopsNameScan`.
    public func sendNameScanTurn(messages: [OpenAIChatRequest.Message]) async throws -> String {
        let prompt = try GoogleAIModePromptBudget.freshPrompt(from: messages, allowsTrimming: false)
        return try await HiddenWebForegroundRunner.run(
            logTag: "[AIMode]",
            shouldStop: { AINameExtractionBatchProcessor.shouldStopBatch(on: $0) },
            exhaustedError: GoogleAIModeError.interruptedInBackground
        ) {
            try await self.runTurn(.fresh(prompt), isScan: true, timeouts: Self.scanTimeouts, onDelta: nil, onMstk: nil)
        }
    }

    /// "Kiểm tra kết nối": luôn là cuộc chat mới, không gắn với phiên nào.
    public func testChatPing(config: AIConfiguration) async throws -> String {
        try await runTurn(
            .fresh("Xin chào, phản hồi lại ngắn gọn: OK"),
            isScan: false,
            timeouts: Self.chatTimeouts,
            onDelta: nil,
            onMstk: nil
        )
    }
}
