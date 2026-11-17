import SwiftUI

/// Nút khắc phục dưới một tin lỗi của provider chạy bằng trang web (1.3.971): "Mở Google để xác minh" cho captcha của Chế
/// độ AI của Google, "Mở ChatGPT" cho lỗi ChatGPT Web cần người dùng tự xử lý trên trang. Một điểm vào cho màn AI và màn
/// Cấu hình AI — thêm provider web mới thì thêm nhánh ở đây, không thêm dòng vào `ReaderAIFullScreenView` (file đó sát
/// trần 400 dòng).
///
/// Nhận biết theo chuỗi lỗi do app sinh (`captchaMarker` / `openBrowserMarker`), **không** thêm field vào
/// `AIChatMessage` — xem `GoogleAIModeError`.
public struct AIWebRecoveryButtons: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        if GoogleAIModeVerifyButton.applies(to: text) {
            GoogleAIModeVerifyButton()
        }
        if ChatGPTWebOpenButton.applies(to: text) {
            ChatGPTWebOpenButton()
        }
    }

    public static func applies(to text: String) -> Bool {
        GoogleAIModeVerifyButton.applies(to: text) || ChatGPTWebOpenButton.applies(to: text)
    }
}
