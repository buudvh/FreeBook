import SwiftData
import SwiftUI

/// Cài đặt **tự động xoá truyện lâu không đọc**: bật/tắt, ngưỡng số ngày, nhịp chạy và nút dọn ngay.
///
/// Cùng khuôn với [`DriveAutoBackupSettingsView`](../Backup/DriveAutoBackupSettingsView.swift): các
/// `@AppStorage` bind đúng khoá mà
/// [`StaleBookCleanupPolicy`](../../../Services/Cleanup/StaleBookCleanupPolicy.swift) đọc, nên không có
/// bản sao thứ hai của cấu hình. Việc xoá luôn đi qua `StaleBookCleanupCoordinator`.
struct StaleBookCleanupSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(StaleBookCleanupPolicy.enabledKey) private var isEnabled = false
    @AppStorage(StaleBookCleanupPolicy.inactiveDaysKey) private var inactiveDays = StaleBookCleanupPolicy.defaultInactiveDays
    @AppStorage(StaleBookCleanupPolicy.modeKey) private var modeRaw = StaleBookCleanupPolicy.Mode.daily.rawValue
    @AppStorage(StaleBookCleanupPolicy.cooldownHoursKey) private var cooldownHours = 24
    @AppStorage(StaleBookCleanupPolicy.dailyHourKey) private var dailyHour = 3

    @State private var lastRunAt = StaleBookCleanupPolicy.lastRunAt
    /// `nil` khi chưa đếm xong; là số truyện sẽ bị xoá nếu dọn ngay lúc này.
    @State private var staleCount: Int?
    @State private var isRunning = false
    @State private var showingRunConfirm = false

    private var mode: StaleBookCleanupPolicy.Mode {
        StaleBookCleanupPolicy.Mode(rawValue: modeRaw) ?? .daily
    }

    /// Slider cần `Double`; setter kẹp lại bằng chính policy để không ghi giá trị ngoài biên.
    private var inactiveDaysValue: Binding<Double> {
        Binding(
            get: { Double(StaleBookCleanupPolicy.clampInactiveDays(inactiveDays)) },
            set: { inactiveDays = StaleBookCleanupPolicy.clampInactiveDays(Int($0.rounded())) }
        )
    }

    var body: some View {
        Form {
            enableSection
            thresholdSection
            if isEnabled {
                scheduleSection
            }
            statusSection
        }
        .navigationTitle("Dọn Truyện Cũ")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshStaleCount()
        }
        .onChange(of: inactiveDays) { _, _ in
            Task { await refreshStaleCount() }
        }
        .confirmationDialog(
            "Xoá truyện lâu không đọc?",
            isPresented: $showingRunConfirm,
            titleVisibility: .visible
        ) {
            Button("Xoá \(pendingCountText) ngay", role: .destructive) {
                runNow()
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Truyện bị xoá cùng toàn bộ chương đã tải, ảnh bìa và tiến độ đọc."
                 + " Thao tác này không thể hoàn tác — muốn giữ lại thì hãy sao lưu trước.")
        }
    }

    // MARK: - Các section

    private var enableSection: some View {
        Section {
            Toggle("Tự động xoá truyện lâu không đọc", isOn: $isEnabled)
        } footer: {
            Text("Mặc định tắt vì đây là thao tác xoá dữ liệu không hoàn tác được. Khi bật, lượt dọn"
                 + " chạy khoảng \(startupDelaySeconds) giây sau khi mở app, xoá cả truyện trên kệ và"
                 + " trong lịch sử nếu quá lâu không đọc.")
        }
    }

    private var thresholdSection: some View {
        Section {
            LabeledContent("Ngưỡng bỏ quên", value: "\(StaleBookCleanupPolicy.clampInactiveDays(inactiveDays)) ngày")
            HStack(spacing: 8) {
                Text("\(StaleBookCleanupPolicy.inactiveDaysRange.lowerBound)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Slider(
                    value: inactiveDaysValue,
                    in: Double(StaleBookCleanupPolicy.inactiveDaysRange.lowerBound)...Double(StaleBookCleanupPolicy.inactiveDaysRange.upperBound),
                    step: 1
                )
                Text("\(StaleBookCleanupPolicy.inactiveDaysRange.upperBound)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Ngưỡng")
        } footer: {
            Text("Truyện có lần đọc gần nhất cũ hơn số ngày này sẽ bị xoá. Sách local/TXT tự nhập,"
                 + " truyện đang tải hoặc đang xuất ebook, và truyện đang được đọc bằng TTS luôn được giữ lại.")
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Nhịp chạy", selection: $modeRaw) {
                ForEach(StaleBookCleanupPolicy.Mode.allCases, id: \.rawValue) { value in
                    Text(value.displayName).tag(value.rawValue)
                }
            }

            switch mode {
            case .cooldown:
                Stepper(value: $cooldownHours, in: 12...336, step: 12) {
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
            LabeledContent("Sẽ bị xoá nếu dọn ngay", value: pendingCountText)
            LabeledContent("Lượt gần nhất", value: lastRunText)
            Button(role: .destructive) {
                showingRunConfirm = true
            } label: {
                HStack {
                    Label("Dọn ngay", systemImage: "trash")
                    if isRunning {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isRunning || staleCount == 0)
        } header: {
            Text("Trạng thái")
        } footer: {
            Text("Dọn ngay bỏ qua cả nhịp chờ và cờ bật/tắt, nhưng vẫn tính là lượt của kỳ này.")
        }
    }

    // MARK: - Hành động

    @MainActor
    private func runNow() {
        let container = modelContext.container
        isRunning = true
        Task {
            let outcome = await StaleBookCleanupCoordinator.runNow(container: container)
            lastRunAt = StaleBookCleanupPolicy.lastRunAt
            isRunning = false
            switch outcome {
            case .skipped:
                ToastManager.shared.show(message: "Không có truyện nào quá \(inactiveDays) ngày không đọc", type: .info)
            case .deleted(let count):
                ToastManager.shared.show(message: "Đã xoá \(count) truyện lâu không đọc", type: .success)
            case .failed(let message):
                ToastManager.shared.show(message: "Dọn truyện cũ thất bại: \(message)", type: .error)
            }
            await refreshStaleCount()
        }
    }

    @MainActor
    private func refreshStaleCount() async {
        let container = modelContext.container
        staleCount = await StaleBookCleanupCoordinator.previewStaleCount(container: container)
    }

    // MARK: - Định dạng

    private var startupDelaySeconds: Int {
        Int(StaleBookCleanupPolicy.startupDelayNanoseconds / 1_000_000_000)
    }

    private var pendingCountText: String {
        guard let staleCount else { return "Đang đếm…" }
        return "\(staleCount) truyện"
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
