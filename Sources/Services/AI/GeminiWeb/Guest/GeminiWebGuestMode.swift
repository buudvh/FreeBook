import Foundation

/// Gemini Web đang chạy ở **chế độ khách** hay bằng tài khoản — bản ghi nhớ đồng bộ cho những chỗ không `await` được
/// (1.3.977).
///
/// Biết chắc khách hay không phải đọc cookie của WKWebView (bất đồng bộ). Màn AI và bộ chia lượt quét tên riêng lại cần
/// câu trả lời ngay, nên `GeminiWebClient` ghi lại ở đây mỗi lần nó vừa biết: `isSignedIn()` (màn AI gọi khi mở, hàng tài
/// khoản gọi khi hiện) và mỗi lượt gửi. Khách thì khác tài khoản ở ba điểm mà các chỗ đó phải theo:
/// - không giữ được hội thoại phía Gemini (cuộc chat khách mất khi nạp lại trang) ⇒ màn AI vẫn gửi cửa sổ tin gần nhất,
///   kể cả khi bật "Lưu chat vào lịch sử Gemini";
/// - lượt quét tên riêng dùng mức chữ của trang (`AINameExtractionBatchProcessor.chatGPTWebCharacterLimit`) và tách
///   chương dài, thay cho 40.000 ký tự của giao thức đã đăng nhập;
/// - không chọn được model (trang khách tự chọn).
enum GeminiWebGuestMode {
    private static let storageKey = "geminiWebLastKnownGuest"

    /// Lần gần nhất app biết thì Gemini Web đang là khách. Chưa từng biết ⇒ `false` (hành vi cũ của bản đã đăng nhập).
    static var isLikelyGuest: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    static func note(isGuest: Bool) {
        guard isLikelyGuest != isGuest else { return }
        UserDefaults.standard.set(isGuest, forKey: storageKey)
        AppLogger.shared.log("🤖 [GeminiWeb] Chế độ: \(isGuest ? "khách (chưa đăng nhập Google)" : "tài khoản Google")")
    }
}
