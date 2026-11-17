import Foundation

/// Client ChatGPT Web (trang `chatgpt.com`, 1.3.971) — bề mặt giống `GoogleAIModeClient` để các chỗ rẽ nhánh theo
/// `apiFormat` gọi được y hệt.
///
/// Không API, không key, **không bắt đăng nhập**: chưa đăng nhập ChatGPT trong trình duyệt của app thì chạy trang ẩn danh
/// (nhanh hơn), đã đăng nhập thì chạy bằng tài khoản đó ở chế độ chat tạm (không vào lịch sử ChatGPT). App mở trang
/// ChatGPT trong WKWebView ẩn (`ChatGPTWebSessionController`), gán
/// câu hỏi vào ô nhập, gửi form và **đọc DOM** (`ChatGPTWebPageContract`). Mọi lượt đi qua một hàng đợi tuần tự
/// (`ChatGPTWebTurnQueue`).
/// - Chat trong Reader (`sendConversationStreaming`): hỏi tiếp ngay trong trang đang mở khi trang còn giữ cuộc chat của
///   phiên, không thì mở cuộc chat mới với đủ ngữ cảnh — `+Conversation.swift`.
/// - Quét tên riêng (`sendNameScanTurn`): mỗi lượt là một cuộc chat **mới**, tạm dừng khi app ở nền.
/// - Không chọn model, không temperature, không tool calling.
///
/// Retry thuộc về đúng tầng này (`+Turn.swift`): một lần, chỉ khi chưa phát chữ nào. `AIRuntimeCoordinator` và
/// `AINameExtractionBatchProcessor` không bọc thêm vòng retry.
public actor ChatGPTWebClient {
    public static let shared = ChatGPTWebClient()

    /// Giá trị `AIProviderProfile.apiFormat` của provider này.
    public static let apiFormat = "chatgptWeb"

    struct Timeouts: Sendable {
        /// Trang không còn dấu hiệu đang viết và không có chữ mới trong khoảng này ⇒ `.timeout`.
        let idle: TimeInterval
        let absolute: TimeInterval
    }

    static let chatTimeouts = Timeouts(idle: 45, absolute: 180)
    static let scanTimeouts = Timeouts(idle: 90, absolute: 240)

    private init() {}

    /// Chat trong Reader. `config` giữ cho giống chữ ký các client khác (không có model để chọn).
    public func sendConversationStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        sessionId: UUID
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: ChatGPTWebError.webViewUnavailable)
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
    /// nền. Lỗi làm dừng cả lần quét: `ChatGPTWebError.stopsNameScan`.
    public func sendNameScanTurn(messages: [OpenAIChatRequest.Message]) async throws -> String {
        let prompt = try ChatGPTWebPromptBudget.freshPrompt(from: messages, allowsTrimming: false)
        return try await HiddenWebForegroundRunner.run(
            logTag: "[ChatGPTWeb]",
            shouldStop: { AINameExtractionBatchProcessor.shouldStopBatch(on: $0) },
            exhaustedError: ChatGPTWebError.interruptedInBackground
        ) {
            try await self.runTurn(.fresh(prompt), isScan: true, timeouts: Self.scanTimeouts, live: nil, onDelta: nil)
        }
    }

    /// "Kiểm tra kết nối": luôn là cuộc chat mới, không gắn với phiên nào.
    public func testChatPing(config: AIConfiguration) async throws -> String {
        try await runTurn(
            .fresh("Xin chào, phản hồi lại ngắn gọn: OK"),
            isScan: false,
            timeouts: Self.chatTimeouts,
            live: nil,
            onDelta: nil
        )
    }
}
