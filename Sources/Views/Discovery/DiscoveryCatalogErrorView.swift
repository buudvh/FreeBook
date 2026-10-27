import SwiftUI

/// Khối lỗi danh mục của `DiscoveryView` khi cả `home` lẫn `genre` không có mục nào: lỗi thật của script (hoặc câu báo
/// nguồn thiếu cả hai script — khi đó `link == nil`), dòng URL lỗi và hai nút "Thử lại" / "Mở link lỗi". Tách file vì
/// `DiscoveryView.swift` là file legacy có baseline dòng. Trình duyệt của nút gắn ở `DiscoveryView` (`.errorLinkBrowser`).
struct DiscoveryCatalogErrorView: View {
    let message: String
    let link: SourceErrorLink?
    @Binding var openingLink: SourceErrorLink?
    /// Tải lại danh mục (`DiscoveryView.loadDiscoveryData`).
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            VStack(spacing: 6) {
                Text(message)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                ErrorLinkCaption(link: link)
            }
            .padding(.horizontal)
            HStack(spacing: 10) {
                Button(action: onRetry) {
                    Label("Thử lại", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                ErrorLinkButton(link: link, presenting: $openingLink, style: .bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }
}
