import SwiftUI

/// Thẻ trạng thái một từ điển chung (VietPhrase, Name…) của màn "Cài đặt dịch thuật".
/// Chuyển nguyên văn từ `SettingsView.swift` (1.3.520).
struct DictionaryCard: View {
    let title: String
    let statusText: String
    let isSet: Bool
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
            
            if isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
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
