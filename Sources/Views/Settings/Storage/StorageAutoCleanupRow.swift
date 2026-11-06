import SwiftUI

/// Hàng "Tự động dọn" đầu màn Dung lượng (1.3.762): lối vào `StorageAutoCleanupSettingsView`, ghi luôn nhịp đang đặt.
/// Đọc `@AppStorage` đúng khoá của `StorageAutoCleanupPolicy` nên quay về từ màn cài đặt là thấy nhịp mới.
struct StorageAutoCleanupRow: View {
    @AppStorage(StorageAutoCleanupPolicy.enabledKey) private var isEnabled = StorageAutoCleanupPolicy.defaultEnabled
    @AppStorage(StorageAutoCleanupPolicy.modeKey) private var modeRaw = StorageAutoCleanupPolicy.defaultMode.rawValue
    @AppStorage(StorageAutoCleanupPolicy.cooldownHoursKey) private var cooldownHours = StorageAutoCleanupPolicy.defaultCooldownHours
    @AppStorage(StorageAutoCleanupPolicy.dailyHourKey) private var dailyHour = StorageAutoCleanupPolicy.defaultDailyHour

    var body: some View {
        NavigationLink(destination: StorageAutoCleanupSettingsView()) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Tự động dọn")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var summary: String {
        StorageAutoCleanupPolicy.summary(
            isEnabled: isEnabled,
            mode: StorageAutoCleanupPolicy.Mode(rawValue: modeRaw) ?? StorageAutoCleanupPolicy.defaultMode,
            cooldownHours: cooldownHours,
            dailyHour: dailyHour
        )
    }
}
