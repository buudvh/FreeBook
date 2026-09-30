import SwiftUI

/// Mục "Nhà Phát Triển" của `SettingsView`. Tách file theo đúng mẫu `BackupSettingsSection` /
/// `TTSSettingsSection`: `SettingsView.swift` đã sát baseline dòng nên mọi mục mới phải ra file riêng.
struct DeveloperSettingsSection: View {
    var body: some View {
        Section {
            NavigationLink(destination: ExtensionDebugServerView()) {
                Label("Debug Server (LAN)", systemImage: "antenna.radiowaves.left.and.right")
            }
        } header: {
            Text("Nhà Phát Triển")
        } footer: {
            Text("Debug Server mở kênh cho VS Code trên cùng mạng LAN để chạy execute(...) của extension và xem trace; mặc định tắt.")
        }
    }
}
