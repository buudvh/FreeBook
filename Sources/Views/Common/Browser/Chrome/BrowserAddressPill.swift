import SwiftUI

/// Ô URL dạng viên giữa thanh kính dưới (mockup 2026-10-30): nút khiên (`BypassBrowserShieldButton`) + tên miền ở giữa +
/// nút tải lại. Chạm tên miền ⇒ chuyển sang ô nhập `URLBarTextField` (tự lấy focus, bôi đen cả URL), Enter thì nạp.
///
/// Nhãn hiển thị suy từ trạng thái tab, không lưu vào `inputUrl`: Home ⇒ "Trang chủ", trang web ⇒ tên miền (bỏ `www.`).
/// `inputUrl` chỉ dùng khi đang nhập — View cha gán trước khi bật `isEditing` (Home ⇒ chuỗi rỗng).
struct BrowserAddressPill: View {
    @ObservedObject var store: BypassBrowserTabStore
    @ObservedObject var tab: BypassBrowserTab
    let isHome: Bool
    @Binding var inputUrl: String
    @Binding var isEditing: Bool
    let onBeginEditing: () -> Void
    let onSubmit: () -> Void
    let onReload: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if isEditing {
                editingContent
            } else {
                displayContent
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(Color.white.opacity(0.10), in: Capsule())
    }

    // MARK: - Hiển thị

    @ViewBuilder
    private var displayContent: some View {
        BypassBrowserShieldButton(store: store, tab: tab, onOpenSettings: onOpenSettings)

        Button(action: onBeginEditing) {
            HStack(spacing: 4) {
                if tab.isIncognito {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .accessibilityLabel("Đang duyệt ẩn danh, không lưu lịch sử")
                }
                Text(hostLabel)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Địa chỉ: \(hostLabel)")
        .accessibilityHint("Chạm để nhập địa chỉ mới")

        Button(action: onReload) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isHome ? "Tải lại trang chủ" : "Tải lại trang")
    }

    private var hostLabel: String {
        if isHome { return "Trang chủ" }
        if let host = URL(string: tab.urlString)?.host, !host.isEmpty {
            return BrowserSitePreferenceStore.normalizedDomain(for: host) ?? host
        }
        return tab.urlString.isEmpty ? "Trang chủ" : tab.urlString
    }

    // MARK: - Đang nhập

    @ViewBuilder
    private var editingContent: some View {
        URLBarTextField(
            placeholder: "Nhập địa chỉ web...",
            text: $inputUrl,
            isEditing: $isEditing,
            onSubmit: onSubmit,
            becomesFirstResponderOnAppear: true
        )
        .padding(.leading, 14)
        .frame(maxWidth: .infinity)

        if !inputUrl.isEmpty {
            Button {
                inputUrl = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 36, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xoá địa chỉ")
        } else {
            Color.clear
                .frame(width: 12, height: 1)
                .accessibilityHidden(true)
        }
    }
}
