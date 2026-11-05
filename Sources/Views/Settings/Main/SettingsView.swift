import SwiftUI

/// Tab Cài đặt: chỉ còn các dòng điều hướng, chia 5 nhóm (1.3.520; nhóm "Chung" thêm sau). Nội dung từng nhóm nằm ở màn riêng —
/// `TranslationSettingsView`, `TTSSettingsHubView`, `BrowserSettingsView`, `LogSettingsView`,
/// `ThermalMonitorView`… — và các section ở `GeneralSettingsSection`, `ReadingSettingsSection`, `LibrarySettingsSection`,
/// `DeveloperSettingsSection`.
struct SettingsView: View {
    /// Bản mới đang mở trong sheet `AppUpdateSheet` (hàng "Có bản mới" của section Thông Tin).
    @State private var sheetUpdate: AppUpdateInfo? = nil

    var body: some View {
        NavigationStack {
            Form {
                GeneralSettingsSection()
                ReadingSettingsSection()
                LibrarySettingsSection()
                DeveloperSettingsSection()

                Section(header: Text("Thông Tin")) {
                    versionRow
                    if let update = AppUpdateRepository.shared.pendingUpdate {
                        appUpdateRow(update)
                    }
                }
            }
            .pageTitle("Cài đặt")
            .mainTabBar() // thanh tab tự vẽ: trong trang gốc, trang đẩy vào phủ lên (1.3.668)
            .sheet(item: $sheetUpdate) { update in
                AppUpdateSheet(update: update)
            }
        }
    }

    /// Dòng "Phiên bản ứng dụng": bấm ⇒ kiểm tra bản mới ngay (1.3.732). Đang kiểm thì vòng xoay thay cho số version;
    /// xong thì toast "Đang dùng bản mới nhất" / mở sheet bản mới / báo lỗi.
    private var versionRow: some View {
        let isChecking = AppUpdateRepository.shared.isChecking
        return Button {
            Task { await checkForUpdate() }
        } label: {
            HStack {
                Text("Phiên bản ứng dụng")
                    .foregroundStyle(.primary)
                Spacer()
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(AppVersionInfo.display)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isChecking)
        .accessibilityHint("Bấm để kiểm tra bản mới")
    }

    private func checkForUpdate() async {
        switch await AppUpdateRepository.shared.checkNow() {
        case .upToDate:
            ToastManager.shared.show(message: "Đang dùng bản mới nhất", type: .success, recordsInInbox: false)
        case .updateAvailable(let update):
            ToastManager.shared.show(message: "Có bản mới \(update.version)", type: .info, recordsInInbox: false)
            sheetUpdate = update
        case .failed:
            ToastManager.shared.show(message: "Không kiểm tra được bản mới", type: .error, recordsInInbox: false)
        }
    }

    /// Hàng "Có bản mới" (`AppUpdateRepository`): còn hiện cả khi đã bấm × ở dải báo của Kệ, chỉ mất khi "Bỏ qua bản
    /// này" hoặc đã lên bản đó. Chấm đỏ = chưa mở sheet của bản này (cùng chấm trên tab Cài Đặt).
    private func appUpdateRow(_ update: AppUpdateInfo) -> some View {
        Button {
            sheetUpdate = update
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.square")
                    .foregroundStyle(Color.accentColor)
                Text("Có bản mới \(update.version)")
                    .foregroundStyle(.primary)
                Spacer()
                if AppUpdateRepository.shared.showsUnseenDot {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
}
