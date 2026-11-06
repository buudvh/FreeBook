import SwiftUI

/// Hàng công tắc "Báo cập nhật khi mở app" trong ngăn kéo … của tab Tiện Ích (1.3.748), mặc định bật.
///
/// Tắt ⇒ mở app không kiểm cập nhật tiện ích, không toast (`ExtensionUpdateCheckCoordinator.checkOnLaunch`); lượt tự
/// kiểm khi vào "Tất cả tiện ích" vẫn chạy. View riêng giữ `@AppStorage` ngay cạnh hàng vì nội dung ngăn kéo vẽ ở cửa
/// sổ riêng, không đọc state của màn.
struct ExtensionLaunchUpdateToggleRow: View {
    @AppStorage(ExtensionUpdateCheckCoordinator.launchCheckEnabledKey) private var isEnabled = true

    var body: some View {
        SideDrawerToggleRow("Báo cập nhật khi mở app", systemImage: "arrow.triangle.2.circlepath", isOn: $isEnabled)
    }
}
