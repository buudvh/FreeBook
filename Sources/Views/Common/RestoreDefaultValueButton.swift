import SwiftUI

/// Nút ↺ **khôi phục mặc định** cạnh một ô nhập — chỉ hiện khi ô có giá trị mặc định khác rỗng và giá trị
/// đang khác mặc định.
///
/// Xoá · sao chép · dán đã do thanh công cụ trên bàn phím lo cho mọi ô nhập; nút này chỉ còn làm việc mà thanh
/// đó không làm được (thanh không biết giá trị mặc định của ô). Dùng ở màn Cấu hình tiện ích (biến cấu hình).
///
/// `.buttonStyle(.borderless)` là bắt buộc: trong một dòng của `Form`, nút kiểu mặc định làm chạm bất kỳ đâu trên
/// dòng là bấm nút này.
struct RestoreDefaultValueButton: View {
    @Binding var text: String
    /// Giá trị mặc định của ô; rỗng hoặc `nil` thì không có nút.
    let defaultValue: String?

    var body: some View {
        if let defaultValue, !defaultValue.isEmpty, text != defaultValue {
            Button(action: { text = defaultValue }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption)
                    .frame(width: 28, height: 26)
                    .foregroundColor(.secondary)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(5)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Khôi phục mặc định")
        } else {
            EmptyView()
        }
    }
}
