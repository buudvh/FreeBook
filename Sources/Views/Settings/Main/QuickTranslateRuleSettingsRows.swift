import SwiftUI

/// Hai dòng "rule dịch" trong section "Dịch Thuật Quick Translate": link màn hình quản lý và công tắc
/// bật/tắt. Tách khỏi `SettingsView` để file đó không phình thêm (đang trong baseline legacy).
struct QuickTranslateRuleSettingsRows: View {
    /// Mặc định **bật**, phải khớp `QuickTranslationRuleStore.isEnabled` — store đọc qua
    /// `object(forKey:)` vì repo không có `UserDefaults.register(defaults:)`, nên hai chỗ cùng mặc
    /// định `true` mới không nhảy trạng thái ở lần mở Cài đặt đầu tiên.
    @AppStorage("isQuickTranslateRuleEnabled") private var isQuickTranslateRuleEnabled = true

    let isTranslationEnabled: Bool
    let isBusy: Bool

    var body: some View {
        // `Group` để hai dòng này thành **hai row** riêng của Section thay vì một row lồng nhau.
        Group {
            NavigationLink(destination: QuickTranslationRulesView()) {
                Label("Quản lý rule dịch", systemImage: "text.badge.checkmark")
            }
            .disabled(isBusy)

            if isTranslationEnabled {
                Toggle(isOn: $isQuickTranslateRuleEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Áp dụng rule dịch")
                            .font(.subheadline)
                        Text("Thay cụm số, đơn vị và mẫu câu theo bộ rule trước khi tách từ. Tắt nếu muốn dịch thuần từ điển.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 16)
                .onChange(of: isQuickTranslateRuleEnabled) { _, _ in
                    // Đúng khuôn ba toggle dịch đang có: dọn cache rồi phát **một** thông báo để
                    // Reader/TTS dựng lại snapshot, không tạo đường refresh thứ hai.
                    TranslateUtils.clearCache()
                    TranslationManager.shared.notifyDictionariesDidUpdate()
                }
            }
        }
    }
}
