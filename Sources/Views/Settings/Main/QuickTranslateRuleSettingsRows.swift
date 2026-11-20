import SwiftUI

/// Cụm "rule dịch" trong panel "Dịch Thuật Quick Translate" (chỉ hiện khi bật Quick Translate): công tắc "Áp dụng rule
/// dịch" rồi, **chỉ khi công tắc bật**, link màn Quản lý rule dịch thụt thêm một bậc — màn quản lý là con của công tắc.
/// Tách khỏi `SettingsView` để file đó không phình thêm (đang trong baseline legacy).
struct QuickTranslateRuleSettingsRows: View {
    /// Mặc định **bật**, phải khớp `QuickTranslationRuleStore.isEnabled` — store đọc qua
    /// `object(forKey:)` vì repo không có `UserDefaults.register(defaults:)`, nên hai chỗ cùng mặc
    /// định `true` mới không nhảy trạng thái ở lần mở Cài đặt đầu tiên.
    @AppStorage("isQuickTranslateRuleEnabled") private var isQuickTranslateRuleEnabled = true

    let isBusy: Bool

    var body: some View {
        // `Group` để các dòng này thành **row** riêng của Section thay vì một row lồng nhau.
        Group {
            // Giải thích nằm trong nút "?" cạnh tên công tắc, không còn dòng chữ phụ luôn hiện. Cỡ chữ `.body` như mọi
            // hàng khác — trước là `.subheadline`, nhỏ hơn chính hàng con "Quản lý rule dịch".
            HelpLabeledToggle(
                title: "Áp dụng rule dịch",
                help: ["Thay cụm số, đơn vị và mẫu câu theo bộ rule trước khi tách từ. Tắt nếu muốn dịch thuần từ điển."],
                isOn: $isQuickTranslateRuleEnabled
            )
            .padding(.leading, 16)
            .onChange(of: isQuickTranslateRuleEnabled) { _, _ in
                // Đúng khuôn ba toggle dịch đang có: dọn cache rồi phát **một** thông báo để
                // Reader/TTS dựng lại snapshot, không tạo đường refresh thứ hai.
                TranslateUtils.clearCache()
                TranslationManager.shared.notifyRulesDidUpdate()
            }

            if isQuickTranslateRuleEnabled {
                NavigationLink(destination: QuickTranslationRulesView()) {
                    Label("Quản lý rule dịch", systemImage: "text.badge.checkmark")
                        .padding(.leading, 32)
                }
                .disabled(isBusy)
            }
        }
    }
}
