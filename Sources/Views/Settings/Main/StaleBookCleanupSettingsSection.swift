import SwiftUI

/// Section mở màn cấu hình tự động dọn truyện lâu không đọc trong màn Cài Đặt.
struct StaleBookCleanupSettingsSection: View {
    var body: some View {
        Section(header: Text("Dọn Dẹp Thư Viện")) {
            NavigationLink(destination: StaleBookCleanupSettingsView()) {
                Label("Tự động xoá truyện lâu không đọc", systemImage: "trash.circle")
            }
        }
    }
}
