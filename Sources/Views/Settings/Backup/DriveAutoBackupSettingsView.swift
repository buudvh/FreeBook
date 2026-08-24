import SwiftData
import SwiftUI

/// Cài đặt **tự động sao lưu lên Google Drive**: bật/tắt, nhịp chạy, nhóm nội dung và nút chạy ngay.
///
/// Cùng khuôn với [`NewChapterSettingsView`](../NewChapters/NewChapterSettingsView.swift): các
/// `@AppStorage` bind đúng key mà [`DriveAutoBackupPolicy`](../../../Services/Backup/DriveAutoBackupPolicy.swift)
/// đọc, nên không có chỗ nào giữ bản sao thứ hai của cấu hình.
struct DriveAutoBackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var coordinator = BackupCoordinator.shared

    @AppStorage(DriveAutoBackupPolicy.enabledKey) private var isEnabled = true
    @AppStorage(DriveAutoBackupPolicy.modeKey) private var modeRaw = DriveAutoBackupPolicy.Mode.cooldown.rawValue
    @AppStorage(DriveAutoBackupPolicy.cooldownHoursKey) private var cooldownHours = 24
    @AppStorage(DriveAutoBackupPolicy.dailyHourKey) private var dailyHour = 22

    @State private var scopes = DriveAutoBackupPolicy.scopes
    @State private var lastRunAt = DriveAutoBackupPolicy.lastRunAt

    private var mode: DriveAutoBackupPolicy.Mode {
        DriveAutoBackupPolicy.Mode(rawValue: modeRaw) ?? .cooldown
    }

    var body: some View {
        Form {
            enableSection
            if isEnabled {
                scheduleSection
            }
            BackupScopeToggleList(selection: $scopes, header: "Nội dung sao lưu tự động")
            statusSection
        }
        .navigationTitle("Tự Động Sao Lưu")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scopes) { _, newValue in
            DriveAutoBackupPolicy.scopes = newValue
        }
        .onChange(of: coordinator.lastError) { _, error in
            guard let error else { return }
            ToastManager.shared.show(message: error, type: .error)
            coordinator.lastError = nil
        }
    }

    // MARK: - Các section

    private var enableSection: some View {
        Section {
            Toggle("Tự động tải lên Google Drive", isOn: $isEnabled)
        } footer: {
            Text("Chỉ chạy khi đã đăng nhập Google Drive, và chạy khoảng nửa phút sau khi mở app để"
                 + " không tranh tài nguyên lúc khởi động. Trên Drive luôn giữ tối đa"
                 + " \(DriveAutoBackupPolicy.maxVersions) bản tự động gần nhất — bản cũ hơn bị xoá,"
                 + " bản bạn tự tạo hoặc tự tải lên không bị chạm tới.")
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Nhịp chạy", selection: $modeRaw) {
                ForEach(DriveAutoBackupPolicy.Mode.allCases, id: \.rawValue) { value in
                    Text(value.displayName).tag(value.rawValue)
                }
            }

            switch mode {
            case .cooldown:
                Stepper(value: $cooldownHours, in: 6...168, step: 6) {
                    LabeledContent("Cách nhau", value: "\(cooldownHours) giờ")
                }
            case .daily:
                Picker("Sau giờ", selection: $dailyHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
            }
        } header: {
            Text("Nhịp chạy")
        } footer: {
            Text(mode == .cooldown
                 ? "Lượt sau chỉ chạy khi đã qua \(cooldownHours) giờ kể từ lượt trước."
                 : "Mỗi ngày đúng một lượt, tính từ \(String(format: "%02d:00", dailyHour)).")
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Google Drive", value: driveStateText)
            LabeledContent("Lượt gần nhất", value: lastRunText)
            Button {
                runNow()
            } label: {
                Label("Sao lưu lên Drive ngay", systemImage: "arrow.up.doc")
            }
            .disabled(coordinator.isBusy || !coordinator.isDriveSignedIn)
        } header: {
            Text("Trạng thái")
        } footer: {
            Text(coordinator.isDriveSignedIn
                 ? "Bấm chạy ngay là bỏ qua nhịp chờ, nhưng vẫn tính là lượt của kỳ này."
                 : "Hãy đăng nhập Google Drive ở màn Sao Lưu & Khôi Phục trước.")
        }
    }

    // MARK: - Hành động

    private func runNow() {
        let container = modelContext.container
        Task {
            let outcome = await coordinator.runAutoDriveBackup(container: container, force: true)
            lastRunAt = DriveAutoBackupPolicy.lastRunAt
            switch outcome {
            case .skipped:
                ToastManager.shared.show(message: "Chưa chạy được lúc này, thử lại sau", type: .error)
            case .succeeded(_, let size, _, _):
                ToastManager.shared.show(message: "Đã tải bản sao lưu \(size) lên Drive", type: .success)
            case .failed(let message):
                ToastManager.shared.show(message: "Sao lưu tự động thất bại: \(message)", type: .error)
            }
        }
    }

    // MARK: - Định dạng

    private var driveStateText: String {
        guard GoogleDriveConfiguration.isConfigured else { return "Chưa cấu hình" }
        return coordinator.isDriveSignedIn ? "Đã đăng nhập" : "Chưa đăng nhập"
    }

    private var lastRunText: String {
        guard let lastRunAt else { return "Chưa chạy" }
        return Self.dateFormatter.string(from: lastRunAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "d/M/yyyy HH:mm"
        return formatter
    }()
}
