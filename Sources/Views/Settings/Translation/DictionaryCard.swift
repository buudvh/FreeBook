import SwiftUI

/// Thẻ trạng thái một từ điển chung (VietPhrase, Name… và Rule dịch) của màn "Cài đặt dịch thuật".
/// Chuyển nguyên văn từ `SettingsView.swift` (1.3.520).
///
/// Thẻ là **nhãn** của `Menu` thả xuống (`GlobalDictionaryCardMenu`): chạm thẻ mở menu Sửa / Nhập / Xuất / Làm mới / Xoá.
/// Cuối thẻ là icon `ellipsis` dọc báo có menu (thay icon xuất phủ lên thẻ của 1.3.638); đang nhập / xuất ⇒ vòng quay.
struct DictionaryCard: View {
    let title: String
    let statusText: String
    let isSet: Bool
    /// Đang nhập / xuất / xoá ⇒ vòng quay ở chỗ icon menu.
    let isLoading: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(isLoading ? .white : (isSet ? .secondary : .red))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .rotationEffect(.degrees(90))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}
