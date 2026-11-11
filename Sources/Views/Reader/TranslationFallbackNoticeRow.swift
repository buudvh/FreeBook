import SwiftUI

/// Hàng báo trong popup dịch (`TranslationScopePopupView`) khi chương đang hiện bị tiện ích dịch lỗi
/// (`TranslationFallbackStatusStore`): dòng có chữ Hán dịch bằng QT thay thế, dòng khác giữ chữ gốc. Nút "Thử lại" xin
/// Reader dựng lại chương (caller gọi `requestRetry` rồi đóng popup).
///
/// Chữ lấy từ `TranslationFallbackStatus.titleText` / `detailText` — một nguồn với dải báo đầu chương của Reader.
struct TranslationFallbackNoticeRow: View {
    let status: TranslationFallbackStatus
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: status.titleText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(verbatim: status.detailText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onRetry) {
                    Text("Thử lại")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.orange.opacity(0.4), lineWidth: 0.5)
        )
    }
}
