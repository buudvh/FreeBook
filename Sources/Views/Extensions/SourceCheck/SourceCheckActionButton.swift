import SwiftUI

/// Nút của thanh hành động dưới đáy hai màn kiểm tra nguồn (Dừng, Chạy lại, Tắt/Xoá/Gỡ nguồn lỗi…): icon trên, chữ
/// dưới, nền màu mờ.
struct SourceCheckActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    init(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundColor(tint)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
