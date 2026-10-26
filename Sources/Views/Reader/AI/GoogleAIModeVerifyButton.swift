import SwiftUI

/// Nút "Mở Google để xác minh" (1.3.609): hiện dưới tin lỗi captcha của Chế độ AI của Google trong màn AI, và dưới kết
/// quả "Kiểm tra kết nối" ở màn Cấu hình AI. Mở trang Chế độ AI trong trình duyệt bypass để người dùng giải captcha
/// (`GoogleAIModeVerificationLauncher`). Kiểu viên thuốc giống `ReaderAINameScanRetryButton`, tông đỏ của tin lỗi.
public struct GoogleAIModeVerifyButton: View {
    public init() {}

    public var body: some View {
        Button(action: { GoogleAIModeVerificationLauncher.shared.open() }) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .semibold))
                Text("Mở Google để xác minh")
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
        .accessibilityLabel("Mở Google trong trình duyệt để xác minh không phải robot")
    }

    /// Nội dung tin/thông báo lỗi là captcha của Chế độ AI.
    public static func applies(to text: String) -> Bool {
        text.contains(GoogleAIModeError.captchaMarker)
    }
}
