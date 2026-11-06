import SwiftData
import SwiftUI

/// Cài đặt **lịch tự động dọn dung lượng** (1.3.762), mở từ hàng "Tự động dọn" đầu màn Dung lượng: bật/tắt, nhịp chạy,
/// mục được dọn và nút dọn ngay.
///
/// Cùng khuôn với [`DriveAutoBackupSettingsView`](../Backup/DriveAutoBackupSettingsView.swift) và
/// [`StaleBookCleanupSettingsView`](StaleBookCleanupSettingsView.swift): `@AppStorage` bind đúng khoá mà
/// `StorageAutoCleanupPolicy` đọc, không có bản sao thứ hai của cấu hình. Việc dọn luôn đi qua
/// `StorageAutoCleanupCoordinator`.
struct StorageAutoCleanupSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(StorageAutoCleanupPolicy.enabledKey) private var isEnabled = StorageAutoCleanupPolicy.defaultEnabled
    @AppStorage(StorageAutoCleanupPolicy.modeKey) private var modeRaw = StorageAutoCleanupPolicy.defaultMode.rawValue
    @AppStorage(StorageAutoCleanupPolicy.cooldownHoursKey) private var cooldownHours = StorageAutoCleanupPolicy.defaultCooldownHours
    @AppStorage(StorageAutoCleanupPolicy.dailyHourKey) private var dailyHour = StorageAutoCleanupPolicy.defaultDailyHour

    @State private var categories = StorageAutoCleanupPolicy.categories
    @State private var lastRunAt = StorageAutoCleanupPolicy.lastRunAt
    @State private var lastFreedBytes = StorageAutoCleanupPolicy.lastFreedBytes
    @State private var isRunning = false
    @State private var showingRunConfirm = false

    private var mode: StorageAutoCleanupPolicy.Mode {
        StorageAutoCleanupPolicy.Mode(rawValue: modeRaw) ?? StorageAutoCleanupPolicy.defaultMode
    }

    /// Mục đang bật, theo thứ tự của màn.
    private var enabledCategories: [StorageUsageCategory] {
        StorageAutoCleanupPolicy.eligibleCategories.filter { categories.contains($0) }
    }

    var body: some View {
        Form {
            enableSection
            if isEnabled {
                scheduleSection
            }
            categorySection
            statusSection
        }
        .backPageTitle("Tự động dọn")
        .onChange(of: categories) { _, newValue in
            StorageAutoCleanupPolicy.categories = newValue
        }
        .confirmationDialog(
            "Dọn các mục đã bật?",
            isPresented: $showingRunConfirm,
            titleVisibility: .visible
        ) {
            Button("Dọn ngay", role: .destructive) {
                runNow()
            }
        } message: {
            Text(enabledCategories.map { StorageAutoCleanupPolicy.title(for: $0) }.joined(separator: ", ") + ".")
        }
    }

    // MARK: - Các section

    private var enableSection: some View {
        Section {
            Toggle("Tự động dọn dung lượng", isOn: $isEnabled)
        } header: {
            SectionHelpHeader("Tự động dọn", paragraphs: [
                "App không chạy nền: tới kỳ thì lượt dọn chạy khoảng \(startupDelaySeconds) giây sau khi mở app, chờ sao lưu / khôi phục đang chạy xong trước. Lượt chạy im lặng; kết quả ở mục Trạng thái.",
                "Chỉ dọn các mục bật bên dưới. Bìa của truyện còn trên Kệ, Lịch sử hay trong thư viện không bao giờ bị xoá."
            ])
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Nhịp chạy", selection: $modeRaw) {
                ForEach(StorageAutoCleanupPolicy.Mode.allCases, id: \.rawValue) { value in
                    Text(value.displayName).tag(value.rawValue)
                }
            }

            switch mode {
            case .cooldown:
                Stepper(value: $cooldownHours, in: StorageAutoCleanupPolicy.cooldownHoursRange, step: 6) {
                    LabeledContent("Cách nhau", value: "\(StorageAutoCleanupPolicy.clampCooldownHours(cooldownHours)) giờ")
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
                 ? "Lượt sau chỉ chạy khi đã qua \(StorageAutoCleanupPolicy.clampCooldownHours(cooldownHours)) giờ kể từ lượt trước."
                 : "Mỗi ngày một lượt, chạy lần đầu mở app sau \(String(format: "%02d:00", dailyHour)).")
        }
    }

    private var categorySection: some View {
        Section {
            ForEach(StorageAutoCleanupPolicy.eligibleCategories) { category in
                Toggle(StorageAutoCleanupPolicy.title(for: category), isOn: binding(for: category))
            }
        } header: {
            SectionHelpHeader("Mục được dọn", paragraphs: [
                "Bìa mồ côi: bìa không còn truyện nào trong thư viện (chủ yếu từ trang Chi tiết của truyện chưa lưu ở bản cũ). Bìa còn dùng mà lớn hơn \(CoverImageEncoder.maxPixelSize) px được thu nhỏ lại, nhìn không khác.",
                "Cache ảnh truyện tranh tải lại khi đọc online; truyện tranh đã tải offline không bị đụng.",
                "File xuất: chỉ bản của tác vụ xuất đã xong, kèm hàng của chúng trong Tải xuống.",
                "Nhật ký dùng để tìm lỗi — tự xoá thì lúc gặp lỗi có thể không còn log để xem.",
                "Báo cáo kiểm tra vốn đã tự giữ 20 bản mới nhất mỗi loại."
            ])
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Lượt gần nhất", value: lastRunText)
            LabeledContent("Đã giải phóng", value: lastFreedBytes.map { StorageUsageSnapshot.format($0) } ?? "—")
            Button {
                showingRunConfirm = true
            } label: {
                HStack {
                    Label("Dọn ngay theo các mục đã bật", systemImage: "sparkles")
                    if isRunning {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isRunning || categories.isEmpty)
        } header: {
            SectionHelpHeader("Trạng thái", paragraphs: ["Dọn ngay bỏ qua cả nhịp chờ và cờ bật/tắt, nhưng vẫn tính là lượt của kỳ này."])
        }
    }

    // MARK: - Hành động

    private func binding(for category: StorageUsageCategory) -> Binding<Bool> {
        Binding(
            get: { categories.contains(category) },
            set: { isOn in
                if isOn {
                    categories.insert(category)
                } else {
                    categories.remove(category)
                }
            }
        )
    }

    @MainActor
    private func runNow() {
        let container = modelContext.container
        isRunning = true
        Task {
            await StorageAutoCleanupCoordinator.waitForBackupIdle()
            let outcome = await StorageAutoCleanupCoordinator.runNow(container: container)
            lastRunAt = StorageAutoCleanupPolicy.lastRunAt
            lastFreedBytes = StorageAutoCleanupPolicy.lastFreedBytes
            isRunning = false
            switch outcome {
            case .skipped:
                ToastManager.shared.show(message: "Chưa bật mục nào để dọn", type: .info)
            case .completed(let freed):
                ToastManager.shared.show(message: "Đã dọn (\(StorageUsageSnapshot.format(freed)))", type: .success)
            case .partial(let freed):
                ToastManager.shared.show(
                    message: "Đã dọn (\(StorageUsageSnapshot.format(freed))), bỏ qua bìa truyện — thử lại sau",
                    type: .info
                )
            }
        }
    }

    // MARK: - Định dạng

    private var startupDelaySeconds: Int {
        Int(StorageAutoCleanupPolicy.startupDelayNanoseconds / 1_000_000_000)
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
