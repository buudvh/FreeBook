import SwiftUI

/// Dòng **"VPN 1.1.1.1"** của sheet hub (1.3.1059, anh Bửu duyệt mockup https://claude.ai/artifact/NqVsj9fYBpdFUJJfzeZi1k,
/// chỗ đặt A): ngay dưới bốn dòng cố định, cùng dáng `FloatingHubMenuRow` (ô ≥ 56 pt, icon 17 pt nửa đậm trong khung 28,
/// tên 15 pt nửa đậm, dòng phụ 12 pt, mũi › 13 pt). Là **lối tắt hành động**, không phải tác vụ đang chạy nên không thuộc
/// `FloatingHubItem.Kind`: luôn chạm được, không tính vào số đang chạy / nháy của nút hub. Chạm ⇒ container đóng sheet xong
/// mới chạy phím tắt (`VPNShortcutRunner`).
struct FloatingHubVPNRow: View {
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("VPN 1.1.1.1")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text("Bấm để bật / tắt")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 6)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Chạy phím tắt bật / tắt VPN 1.1.1.1"))
        .hubSheetPanelRow()
    }
}
