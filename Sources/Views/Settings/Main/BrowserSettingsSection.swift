import SwiftUI

/// Section cài đặt trình duyệt hiển thị (Visible Browser) trong màn Cài Đặt.
/// Tách khỏi `SettingsView` để file đó không phình thêm dòng.
struct BrowserSettingsSection: View {
    @AppStorage(VisibleBrowserSettings.openMinimizedKey) private var openMinimized = false

    var body: some View {
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
}
