import SwiftUI

/// Thẻ trạng thái một từ điển chung (VietPhrase, Name…) của màn "Cài đặt dịch thuật".
/// Chuyển nguyên văn từ `SettingsView.swift` (1.3.520).
///
/// Icon xuất TXT (1.3.638) **không** nằm trong thẻ: thẻ là nhãn của nút Nhập, nên nút Xuất được màn cha phủ lên
/// (`overlay`) — lồng nút trong nhãn nút thì chạm lẫn nhau. Thẻ chỉ chừa chỗ trống cuối thẻ cho icon đó.
struct DictionaryCard: View {
    let title: String
    let statusText: String
    let isSet: Bool
    let isLoading: Bool
    /// Đang xuất TXT ⇒ hiện vòng quay ở chỗ icon xuất.
    var isExporting = false
    /// Chừa ô 32×32 cuối thẻ cho icon xuất do màn cha phủ lên.
    var reservesExportSlot = false
    
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
                    .foregroundColor(isLoading || isExporting ? .white : (isSet ? .secondary : .red))
                    .lineLimit(1)
            }
            
            if isLoading || isExporting {
                Spacer()
                ProgressView()
                    .controlSize(.small)
            } else if reservesExportSlot {
                Spacer(minLength: 0)
                Color.clear
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
