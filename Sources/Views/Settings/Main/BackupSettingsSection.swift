import SwiftUI

/// Section mở màn Sao lưu & Khôi phục trong màn Cài Đặt.
struct BackupSettingsSection: View {
    var body: some View {
        Section(header: Text("Sao Lưu & Khôi Phục")) {
            NavigationLink(destination: BackupHubView()) {
                Label("Sao lưu & khôi phục dữ liệu", systemImage: "externaldrive.badge.timemachine")
            }
        }
    }
}
