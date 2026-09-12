import SwiftData
import SwiftUI

/// Cài đặt lịch dùng chung cho Google Drive và Telegram.
///
/// Cùng khuôn với [`NewChapterSettingsView`](../NewChapters/NewChapterSettingsView.swift): các
/// `@AppStorage` bind đúng key mà [`DriveAutoBackupPolicy`](../../../Services/Backup/DriveAutoBackupPolicy.swift)
/// đọc, nên không có chỗ nào giữ bản sao thứ hai của cấu hình.
struct DriveAutoBackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var coordinator = BackupCoordinator.shared

    @AppStorage(DriveAutoBackupPolicy.enabledKey) private var isEnabled = true
    @AppStorage(DriveAutoBackupPolicy.telegramEnabledKey) private var isTelegramEnabled = false
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
            if isEnabled || isTelegramEnabled {
                scheduleSection
            }
            BackupScopeToggleList(selection: $scopes, header: "Nội dung sao lưu tự động")
            statusSection
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
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
            Toggle("Tự động gửi qua Telegram", isOn: $isTelegramEnabled)
                .disabled(!TelegramConfiguration.isConfigured)
        } footer: {
            Text("Hai đích dùng chung lịch và nhóm nội dung, nhưng chạy độc lập. Mỗi kỳ chỉ tạo một archive. Telegram cần cấu hình Bot trước; Drive giữ tối đa \(DriveAutoBackupPolicy.maxVersions) bản tự động gần nhất.")
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
            LabeledContent("Telegram", value: TelegramConfiguration.isConfigured ? "Đã cấu hình" : "Chưa cấu hình")
            LabeledContent("Lượt gần nhất", value: lastRunText)
            Button {
                runNow()
            } label: {
                Label("Sao lưu tới các đích ngay", systemImage: "arrow.up.doc")
            }
            .disabled(coordinator.isBusy || !hasReadyDestination)
        } header: {
            Text("Trạng thái")
        } footer: {
            Text("Bấm chạy ngay là bỏ qua nhịp chờ, nhưng vẫn tính là lượt của kỳ này.")
        }
    }

    // MARK: - Hành động

    private func runNow() {
        let container = modelContext.container
        Task {
            let outcome = await coordinator.runAutoDriveBackup(container: container, force: true)
            lastRunAt = DriveAutoBackupPolicy.lastRunAt
            switch outcome {
            case .skipped(.driveNotLinked):
                ToastManager.shared.show(message: "Chưa đăng nhập Google Drive", type: .error)
            case .skipped(.telegramNotConfigured):
                ToastManager.shared.show(message: "Chưa cấu hình Telegram", type: .error)
            case .skipped(.notDue):
                ToastManager.shared.show(message: "Chưa chạy được lúc này, thử lại sau", type: .error)
            case .completed(_, let size, let driveSent, let telegramSent, let failures, _, _, let pruneIncomplete):
                let destinations = [driveSent ? "Drive" : nil, telegramSent ? "Telegram" : nil]
                    .compactMap { $0 }.joined(separator: " và ")
                let failureNote = failures.isEmpty ? "" : " — " + failures.joined(separator: "; ")
                ToastManager.shared.show(
                    message: "Đã tạo bản sao lưu \(size)" + (destinations.isEmpty ? "" : " và gửi tới \(destinations)")
                        + failureNote + outcome.pruneNote,
                    type: failures.isEmpty && !pruneIncomplete ? .success : .info
                )
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

    private var hasReadyDestination: Bool {
        (isEnabled && GoogleDriveConfiguration.isConfigured && coordinator.isDriveSignedIn)
            || (isTelegramEnabled && TelegramConfiguration.isConfigured)
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
