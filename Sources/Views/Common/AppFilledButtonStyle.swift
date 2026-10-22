import SwiftUI

/// Nút **nền đặc** chuẩn của app: chữ trắng trên một màu cố định (mặc định xanh), mờ khi nhấn và khi bị tắt.
///
/// Vì sao phải có: `MainTabView` đặt `.tint(.white)` toàn cục, nên `Color.accentColor` **là màu trắng** và
/// `.borderedProminent` không kèm `.tint(…)` là **nền trắng** — đặt chữ trắng lên là vô hình (lỗi đã gặp ở 1.3.447 và
/// 1.3.567). Nút đặc mới dùng `.buttonStyle(.appFilled)` / `.appFilled(.purple)` thay vì tự tô nền bằng màu nhấn;
/// `check_architecture.py` (luật `WHITE_TINT_FILL`) chặn hai mẫu sai trong `Sources/Views/**`.
///
/// ```swift
/// Button("Đăng nhập", action: submit)
///     .buttonStyle(.appFilled)
/// Button(action: run) { Label("Chạy", systemImage: "play.fill") }
///     .buttonStyle(.appFilled(.green, fullWidth: false))
/// ```
struct AppFilledButtonStyle: ButtonStyle {
    var color: Color = .blue
    /// `true`: giãn hết bề ngang (nút chính cuối form). `false`: ôm nội dung (nút trên một hàng).
    var fullWidth = true
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        FilledLabel(configuration: configuration, color: color, fullWidth: fullWidth, cornerRadius: cornerRadius)
    }

    /// Tách view riêng để đọc `isEnabled` (ButtonStyle không đọc được Environment trực tiếp).
    private struct FilledLabel: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let fullWidth: Bool
        let cornerRadius: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
                .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: cornerRadius))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension ButtonStyle where Self == AppFilledButtonStyle {
    /// Nút nền đặc xanh, giãn hết bề ngang.
    static var appFilled: AppFilledButtonStyle { AppFilledButtonStyle() }

    /// Nút nền đặc với màu tuỳ chọn — **không** truyền `.white`/`.accentColor` (trắng trên trắng).
    static func appFilled(_ color: Color, fullWidth: Bool = true) -> AppFilledButtonStyle {
        AppFilledButtonStyle(color: color, fullWidth: fullWidth)
    }
}
