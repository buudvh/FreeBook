import SwiftUI

/// Tab Cài đặt: chỉ còn các dòng điều hướng, chia 5 nhóm (1.3.520; nhóm "Chung" thêm sau). Nội dung từng nhóm nằm ở màn riêng —
/// `TranslationSettingsView`, `TTSSettingsHubView`, `BrowserSettingsView`, `LogSettingsView`,
/// `ThermalMonitorView`… — và các section ở `GeneralSettingsSection`, `ReadingSettingsSection`, `LibrarySettingsSection`,
/// `DeveloperSettingsSection`.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                GeneralSettingsSection()
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
            .pageTitle("Cài đặt")
        }
    }
}

#Preview {
    SettingsView()
}
