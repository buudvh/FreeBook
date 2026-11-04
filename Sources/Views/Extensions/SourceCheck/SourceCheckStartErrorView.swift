import SwiftUI

/// Màn báo không bắt đầu được lượt kiểm tra của hai màn kiểm tra nguồn. Lỗi bận ⇒ nút dừng lượt kia; lượt kia đang thu
/// nhỏ (1.3.697) ⇒ thêm nút mở lại nó.
struct SourceCheckStartErrorView: View {
    let message: String
    var onOpenRunning: (() -> Void)?
    var onStopRunning: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let onOpenRunning {
                Button("Mở lượt đang chạy", action: onOpenRunning)
                    .buttonStyle(.bordered)
            }
            if let onStopRunning {
                Button("Dừng lượt đang chạy", action: onStopRunning)
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
    }
}
