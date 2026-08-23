import SwiftUI

/// Section mở màn cấu hình kiểm tra chương mới trong màn Cài Đặt.
struct NewChapterSettingsSection: View {
    var body: some View {
        Section(header: Text("Chương Mới")) {
            NavigationLink(destination: NewChapterSettingsView()) {
                Label("Kiểm tra chương mới", systemImage: "bell.badge")
            }
        }
    }
}
