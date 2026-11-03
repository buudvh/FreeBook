import SwiftUI

/// Nút **nền đặc** chuẩn của app: chữ trắng trên nền màu (mặc định màu nhấn), mờ khi nhấn và khi bị tắt.
///
/// Màu nhấn do người dùng chọn (`AppAccentColor`, mặc định Xanh ngọc; không còn là trắng) ⇒ `.appFilled` mặc định
/// đổi theo lựa chọn đó. Vì sao nền nhấn đặc vẫn phải đi qua đây: nền nhấn đổi theo màu người dùng chọn, nên cần **một**
/// chỗ quyết định màu chữ trên nền đó thay vì mỗi màn tự tô `Color.accentColor` / `.borderedProminent` rồi tự chọn
/// màu chữ (trước đây màu nhấn trắng ⇒ chữ trắng vô hình, lỗi 1.3.447 và 1.3.572). Nút đặc mới dùng
/// `.buttonStyle(.appFilled)` / `.appFilled(.purple)`; `check_architecture.py` (luật `WHITE_TINT_FILL`) chặn hai mẫu
/// tự tô trong `Sources/Views/**`.
///
/// ```swift
/// Button("Đăng nhập", action: submit)
///     .buttonStyle(.appFilled)
/// Button(action: run) { Label("Chạy", systemImage: "play.fill") }
///     .buttonStyle(.appFilled(.green, fullWidth: false))
/// ```
struct AppFilledButtonStyle: ButtonStyle {
    var color: Color = .accentColor
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
    /// Nút nền đặc màu nhấn, giãn hết bề ngang.
    static var appFilled: AppFilledButtonStyle { AppFilledButtonStyle() }

    /// Nút nền đặc với màu tuỳ chọn — **không** truyền `.white` (chữ trắng trên nền trắng); màu nhấn thì dùng
    /// `.appFilled` mặc định.
    static func appFilled(_ color: Color, fullWidth: Bool = true) -> AppFilledButtonStyle {
        AppFilledButtonStyle(color: color, fullWidth: fullWidth)
    }
}
