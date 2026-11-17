import SwiftUI

/// Nút "Mở ChatGPT" (1.3.971): hiện dưới tin lỗi của ChatGPT Web mà người dùng phải tự xử lý trên trang (bước kiểm tra của
/// Cloudflare, hộp mời đăng nhập, hết lượt hỏi ẩn danh, trình duyệt của app đang đăng nhập ChatGPT) trong màn AI, và dưới
/// kết quả "Kiểm tra kết nối" ở màn Cấu hình AI. Mở trang ChatGPT trong trình duyệt bypass (`ChatGPTWebBrowserLauncher`).
/// Cùng kiểu viên thuốc tông đỏ với `GoogleAIModeVerifyButton`.
public struct ChatGPTWebOpenButton: View {
    public init() {}

    public var body: some View {
        Button(action: { ChatGPTWebBrowserLauncher.shared.open() }) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .semibold))
                Text("Mở ChatGPT")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundColor(.red)
            .background(Capsule().fill(Color.red.opacity(0.15)))
            .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mở ChatGPT trong trình duyệt của app")
    }

    /// Nội dung tin/thông báo lỗi là lỗi ChatGPT Web cần mở trang.
    public static func applies(to text: String) -> Bool {
        text.contains(ChatGPTWebError.openBrowserMarker)
    }
}
