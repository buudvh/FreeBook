import Foundation

/// Gemini Web **không đăng nhập** (chế độ khách, 1.3.977).
///
/// Anh Bửu: "gemini web cũng có thể hoạt động tốt dù không đăng nhập". Trang khách không có token `SNlM0e` và không gọi
/// `StreamGenerate` (xem `GeminiWebGuestPageContract`), nên lượt khách **không** đi qua `GeminiWebSessionController` /
/// `GeminiWebRequestBuilder`: nó chạy bằng bộ điều khiển trang ẩn dùng chung với ChatGPT Web
/// (`ChatGPTWebClient.geminiGuest`) — gõ câu hỏi vào ô nhập của trang, bấm gửi, đọc câu trả lời từ DOM.
///
/// - Mỗi lượt là một cuộc chat **mới** (trang khách không khôi phục được cuộc chat sau khi nạp lại): trả về metadata
///   rỗng nên `runConversationTurn` lượt sau lại dựng prompt đủ ngữ cảnh. Màn AI gửi kèm cửa sổ tin gần nhất
///   (`GeminiWebGuestMode`).
/// - Không model (trang tự chọn), không chat tạm / lưu lịch sử (khách không có lịch sử).
/// - Lỗi của bộ điều khiển trang (`ChatGPTWebError`) đổi sang `GeminiWebError` ở đây để mọi chỗ đang xử lý lỗi Gemini Web
///   (dừng quét khi hết hạn mức / bị chặn, thông điệp trong màn AI) chạy như cũ.
extension GeminiWebClient {
    /// `true` = chưa đăng nhập Google ⇒ lượt này chạy chế độ khách. Ghi luôn vào `GeminiWebGuestMode`.
    func resolveGuestMode() async -> Bool {
        let signedIn = await GeminiWebSessionController.shared.isSignedIn()
        GeminiWebGuestMode.note(isGuest: !signedIn)
        return !signedIn
    }

    /// Một lượt sinh nội dung trên trang khách. Luôn trả metadata rỗng (không có cuộc chat nào để nối tiếp).
    func runGuestGeneration(
        prompt: String,
        idleTimeout: TimeInterval,
        absoluteTimeout: TimeInterval,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> [String?] {
        AppLogger.shared.log("🤖 [GeminiWeb] Chưa đăng nhập Google — chạy lượt này ở chế độ khách (\(prompt.count) ký tự)")
        do {
            _ = try await ChatGPTWebClient.geminiGuest.runTurn(
                .fresh(prompt),
                isScan: false,
                timeouts: ChatGPTWebClient.Timeouts(idle: idleTimeout, absolute: absoluteTimeout),
                live: nil,
                onDelta: onDelta
            )
        } catch let error as ChatGPTWebError {
            throw GeminiWebError(guest: error)
        }
        return GeminiWebConversationState.emptyMetadata
    }
}

extension GeminiWebError {
    /// Lỗi của bộ điều khiển trang ẩn (chạy trang Gemini khách) đổi sang lỗi Gemini Web tương ứng.
    init(guest error: ChatGPTWebError) {
        switch error {
        case .captchaRequired:
            // Google chuyển sang trang `/sorry` (nghi bot) — cùng nghĩa với mã 1060 của bản đã đăng nhập.
            self = .ipBlocked
        case .loginPrompt, .loginRequired:
            self = .notSignedIn
        case .rateLimited:
            self = .usageLimit
        case .blocked(let detail), .generationFailed(let detail), .pageLoadFailed(let detail):
            self = .script("trang khách: \(detail)")
        case .requestTooLong:
            self = .protocolChanged("trang khách: câu hỏi quá dài")
        case .emptyResponse:
            self = .emptyResponse(completed: true)
        case .timeout:
            self = .timeout
        case .threadUnavailable, .webViewUnavailable:
            self = .sessionUnavailable
        case .protocolChanged(let detail):
            self = .protocolChanged("trang khách: \(detail)")
        case .interruptedInBackground:
            self = .interruptedInBackground
        }
    }
}
