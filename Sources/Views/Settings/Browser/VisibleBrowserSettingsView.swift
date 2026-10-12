import SwiftUI

/// Màn "Trình duyệt hiển thị" (Cài đặt → Đọc & Nghe). Chuyển nguyên công tắc từ `BrowserSettingsSection` cũ
/// (1.3.520).
struct VisibleBrowserSettingsView: View {
    @AppStorage(VisibleBrowserSettings.openMinimizedKey) private var openMinimized = false

    var body: some View {
        Form {
            Section(header: Text("Trình Duyệt Hiển Thị")) {
                Toggle(isOn: $openMinimized) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mở trình duyệt ở chế độ thu nhỏ")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Khi extension mở trình duyệt hiển thị mới, trình duyệt khởi tạo ngay ở dạng thu nhỏ (widget nổi) thay vì bật lên toàn màn hình. Trình duyệt đang mở không bị ảnh hưởng.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
        .navigationTitle("Trình duyệt hiển thị")
        .navigationBarTitleDisplayMode(.inline)
    }
}
