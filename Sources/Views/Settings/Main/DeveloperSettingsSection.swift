import SwiftUI

/// Mục "Nhà Phát Triển" của `SettingsView`. Tách file theo đúng mẫu `BackupSettingsSection` /
/// `TTSSettingsSection`: `SettingsView.swift` đã sát baseline dòng nên mọi mục mới phải ra file riêng.
struct DeveloperSettingsSection: View {
    var body: some View {
        Section {
            NavigationLink(destination: ExtensionDebugConsoleView()) {
                Label("Debug Extension", systemImage: "ladybug")
            }
            NavigationLink(destination: ExtensionDebugServerView()) {
                Label("Debug Server (LAN)", systemImage: "antenna.radiowaves.left.and.right")
            }
        } header: {
            Text("Nhà Phát Triển")
        } footer: {
            Text("Chạy execute(...) của extension đã cài và xem trace console/fetch/exception thời gian thực. Debug Server mở kênh cho VS Code trên cùng mạng LAN; mặc định tắt.")
        }
    }
}
