import SwiftUI

/// Tab Cài đặt: chỉ còn các dòng điều hướng, chia 5 nhóm (1.3.520; nhóm "Chung" thêm sau). Nội dung từng nhóm nằm ở màn riêng —
/// `TranslationSettingsView`, `TTSSettingsHubView`, `BrowserSettingsView`, `LogSettingsView`,
/// `ThermalMonitorView`… — và các section ở `GeneralSettingsSection`, `ReadingSettingsSection`, `LibrarySettingsSection`,
/// `DeveloperSettingsSection`.
struct SettingsView: View {
    @Environment(\.openURL) private var openURL

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
                        Text(AppVersionInfo.display)
                            .foregroundColor(.secondary)
                    }
                    liveContainerSourceRow
                }
            }
            .pageTitle("Cài đặt")
            .mainTabBar() // thanh tab tự vẽ: trong trang gốc, trang đẩy vào phủ lên (1.3.668)
        }
    }

    /// Nguồn cập nhật cho LiveContainer (`AppDistributionSource`): bấm chữ ⇒ mở LiveContainer, thêm nguồn; nút sao chép
    /// ⇒ chép link để dán tay vào tab Sources. Hai nút `.borderless` để chạm nút nào chạy nút đó, không cả hàng.
    private var liveContainerSourceRow: some View {
        HStack(spacing: 8) {
            Button {
                guard let url = AppDistributionSource.liveContainerAddSourceURL else { return }
                openURL(url) { accepted in
                    if !accepted {
                        ToastManager.shared.show(message: "Không mở được LiveContainer", type: .error, recordsInInbox: false)
                    }
                }
            } label: {
                Label("Thêm nguồn cập nhật vào LiveContainer", systemImage: "plus.app")
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 4)

            Button {
                ClipboardCopier.copy(AppDistributionSource.sourceURLString, message: "Đã sao chép link nguồn")
            } label: {
                AppGlyph.copy.image(size: 17)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Sao chép link nguồn LiveContainer")
        }
    }
}

#Preview {
    SettingsView()
}
