import SwiftUI

/// Tab Cài đặt: chỉ còn các dòng điều hướng, chia 4 nhóm (1.3.520). Nội dung từng nhóm nằm ở màn riêng —
/// `TranslationSettingsView`, `TTSSettingsHubView`, `VisibleBrowserSettingsView`, `LogSettingsView`,
/// `ThermalMonitorView`… — và các section ở `ReadingSettingsSection`, `LibrarySettingsSection`,
/// `DeveloperSettingsSection`.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                ReadingSettingsSection()
                LibrarySettingsSection()
                DeveloperSettingsSection()

                Section(header: Text("Thông Tin")) {
                    HStack {
                        Text("Phiên bản ứng dụng")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
            .navigationTitle("Cài Đặt")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SettingsView()
}
