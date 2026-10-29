import SwiftUI
import Combine

/// Mục "Nhà Phát Triển" của `SettingsView`: các công cụ chẩn đoán — Debug Server, "Ghi log hệ thống" và
/// "Theo dõi nhiệt" (1.3.520). Mức nhiệt đọc thẳng `ProcessInfo` và cập nhật khi iOS báo đổi mức — không
/// observe `TTSManager`.
struct DeveloperSettingsSection: View {
    @AppStorage("isLoggingEnabled") private var isLoggingEnabled = false
    @State private var thermalLevel = ProcessInfo.processInfo.thermalState.rawValue

    var body: some View {
        Section {
            NavigationLink(destination: ExtensionDebugServerView()) {
                Label("Debug Server (LAN)", systemImage: "antenna.radiowaves.left.and.right")
            }
            NavigationLink(destination: LogSettingsView()) {
                LabeledContent {
                    Text(isLoggingEnabled ? "Đang bật" : "Tắt")
                } label: {
                    Label("Ghi log hệ thống", systemImage: "doc.text")
                }
            }
            NavigationLink(destination: ThermalMonitorView()) {
                LabeledContent {
                    Text(ThermalMonitorView.levelName(thermalLevel))
                } label: {
                    Label("Theo dõi nhiệt", systemImage: "thermometer.medium")
                }
            }
        } header: {
            SectionHelpHeader("Nhà Phát Triển", paragraphs: ["Debug Server mở kênh cho VS Code trên cùng mạng LAN; Ghi log hệ thống: bật/tắt log, xem và xuất các file log; Theo dõi nhiệt: mức nhiệt, CPU và pin theo thời gian."])
        }
        .onAppear {
            thermalLevel = ProcessInfo.processInfo.thermalState.rawValue
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            thermalLevel = ProcessInfo.processInfo.thermalState.rawValue
        }
    }
}
