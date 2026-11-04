import SwiftUI

/// Section "Thư Viện" của tab Cài đặt (1.3.520): gom 3 dòng trước đây mỗi dòng một section riêng
/// (`NewChapterSettingsSection`, `BackupSettingsSection`, `StaleBookCleanupSettingsSection`). Đích, nhãn và icon
/// giữ nguyên. "Nội dung nhạy cảm" và "Kiểu hiển thị danh sách" chuyển vào Chung › Giao diện từ 1.3.636.
/// "Truyện mất nguồn" (1.3.690): cách chuyển truyện có tiện ích nguồn đã gỡ sang tiện ích khớp link
/// (`MissingSourceRebindBanner`).
struct LibrarySettingsSection: View {
    @AppStorage(MissingSourceRebindMode.defaultsKey) private var missingSourceRebindMode: MissingSourceRebindMode = .ask

    var body: some View {
        Section(header: Text("Thư Viện")) {
            NavigationLink(destination: NewChapterSettingsView()) {
                Label("Kiểm tra chương mới", systemImage: "bell.badge")
            }
            NavigationLink(destination: BackupHubView()) {
                Label("Sao lưu & khôi phục dữ liệu", systemImage: "externaldrive.badge.timemachine")
            }
            NavigationLink(destination: StaleBookCleanupSettingsView()) {
                Label("Tự động xoá truyện lâu không đọc", systemImage: "trash.circle")
            }
            Picker(selection: $missingSourceRebindMode) {
                ForEach(MissingSourceRebindMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label("Truyện mất nguồn", systemImage: "arrow.triangle.swap")
            }
        }
    }
}
