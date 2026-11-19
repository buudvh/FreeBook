import SwiftUI

/// Hàng pill **"Thử rule"** ở đầu danh sách rule (`QuickTranslationRuleListView`, cả ba phạm vi): icon ống nghiệm + chữ
/// màu nhấn, nền nhấn mờ ~18%, viền ~60% (kiểu chip đang chọn của `ExtensionKindFilterBar`), chevron phải. Chạm ⇒ màn
/// cha mở `QuickTranslationRuleTesterSheet` (sheet gắn ở thân danh sách, không gắn trong hàng — hàng `List` dựng lười).
struct QuickTranslationRuleTesterPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 15, weight: .semibold))
                Text("Thử rule")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(Color.accentColor.opacity(0.18))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Mở ô thử một câu với bộ rule này")
    }
}
