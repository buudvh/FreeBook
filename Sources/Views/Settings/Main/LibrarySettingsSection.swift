import SwiftUI

/// Section "Thư Viện" của tab Cài đặt (1.3.520): gom 3 dòng trước đây mỗi dòng một section riêng
/// (`NewChapterSettingsSection`, `BackupSettingsSection`, `StaleBookCleanupSettingsSection`). Đích, nhãn và icon
/// giữ nguyên.
struct LibrarySettingsSection: View {
    var body: some View {
        Section(header: Text("Thư Viện")) {
            NavigationLink(destination: NsfwSettingsView()) {
                Label("Nội dung nhạy cảm (NSFW)", systemImage: "eye.slash")
            }
            NavigationLink(destination: NewChapterSettingsView()) {
                Label("Kiểm tra chương mới", systemImage: "bell.badge")
            }
            NavigationLink(destination: BackupHubView()) {
                Label("Sao lưu & khôi phục dữ liệu", systemImage: "externaldrive.badge.timemachine")
            }
            NavigationLink(destination: StaleBookCleanupSettingsView()) {
                Label("Tự động xoá truyện lâu không đọc", systemImage: "trash.circle")
            }
        }
    }
}
