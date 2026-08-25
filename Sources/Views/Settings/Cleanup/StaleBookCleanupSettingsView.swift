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

    /// Giá trị đang có hiệu lực — luôn đọc qua policy để giá trị cũ ngoài biên vẫn hiển thị đúng.
    private var clampedInactiveDays: Int {
        StaleBookCleanupPolicy.clampInactiveDays(inactiveDays)
    }

    /// Slider cần `Double`; setter kẹp lại bằng chính policy để không ghi giá trị ngoài biên.
    private var inactiveDaysValue: Binding<Double> {
        Binding(
            get: { Double(StaleBookCleanupPolicy.clampInactiveDays(inactiveDays)) },
            set: { inactiveDays = StaleBookCleanupPolicy.clampInactiveDays(Int($0.rounded())) }
        )
    }

    /// Nút −/+ bước 1 ngày kèm slider: slider kéo tay rất khó dừng đúng một ngày trên dải 7…365.
    ///
    /// `buttonStyle(.borderless)` là bắt buộc trong `Form`, nếu không cả hàng thành một vùng bấm
    /// và bấm chỗ nào cũng lọt vào nút.
    private func nudgeButton(systemImage: String, delta: Int) -> some View {
        Button {
            inactiveDays = StaleBookCleanupPolicy.clampInactiveDays(clampedInactiveDays + delta)
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(delta < 0
                  ? clampedInactiveDays <= StaleBookCleanupPolicy.inactiveDaysRange.lowerBound
                  : clampedInactiveDays >= StaleBookCleanupPolicy.inactiveDaysRange.upperBound)
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
                 + " chạy khoảng \(startupDelaySeconds) giây sau khi mở app và chỉ xoá truyện trong"
                 + " lịch sử — truyện đã thêm vào Kệ sách không bao giờ bị dọn.")
        }
    }

    private var thresholdSection: some View {
        Section {
            LabeledContent("Ngưỡng bỏ quên", value: "\(clampedInactiveDays) ngày")
            HStack(spacing: 10) {
                nudgeButton(systemImage: "minus", delta: -1)
                VStack(spacing: 2) {
                    Slider(
                        value: inactiveDaysValue,
                        in: Double(StaleBookCleanupPolicy.inactiveDaysRange.lowerBound)...Double(StaleBookCleanupPolicy.inactiveDaysRange.upperBound),
                        step: 1
                    )
                    HStack {
                        Text("\(StaleBookCleanupPolicy.inactiveDaysRange.lowerBound)")
                        Spacer()
                        Text("\(StaleBookCleanupPolicy.inactiveDaysRange.upperBound)")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                nudgeButton(systemImage: "plus", delta: 1)
            }
        } header: {
            Text("Ngưỡng")
        } footer: {
            Text("Truyện trong lịch sử có lần đọc gần nhất cũ hơn số ngày này sẽ bị xoá. Truyện trên Kệ"
                 + " sách, sách local/TXT tự nhập, truyện đang tải hoặc đang xuất ebook, và truyện đang"
                 + " được đọc bằng TTS luôn được giữ lại.")
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
                ToastManager.shared.show(message: "Không có truyện nào quá \(clampedInactiveDays) ngày không đọc", type: .info)
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
