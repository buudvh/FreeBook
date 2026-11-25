import SwiftUI

/// Dòng **"VPN 1.1.1.1"** của sheet hub (1.3.1059, chỗ đặt A; hai nút Bật / Tắt 1.3.1061, anh Bửu duyệt mockup bản 3
/// https://claude.ai/artifact/NqVsj9fYBpdFUJJfzeZi1k): ngay dưới bốn dòng cố định, cùng dáng `FloatingHubMenuRow` (ô ≥ 56 pt,
/// icon 17 pt nửa đậm trong khung 28, tên 15 pt nửa đậm, dòng phụ 12 pt). Cuối dòng là hai nút nhỏ Bật / Tắt cao 32, chữ
/// 13 pt nửa đậm — Bật kiểu chip đang chọn (chữ màu nhấn, nền nhấn 18%, viền 60%), Tắt nền trắng 12%. Thân dòng không bấm
/// được (không mũi ›). Là **lối tắt hành động**, không phải tác vụ đang chạy nên không thuộc `FloatingHubItem.Kind`: không
/// tính vào số đang chạy / nháy của nút hub. Bấm nút ⇒ container đóng sheet xong mới chạy phím tắt (`VPNShortcutRunner`).
struct FloatingHubVPNRow: View {
    let onRun: (VPNShortcutLauncher.Action) -> Void

    var body: some View {
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
                Text("Chạy phím tắt")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                actionButton(.on)
                actionButton(.off)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .hubSheetPanelRow()
    }

    private func actionButton(_ action: VPNShortcutLauncher.Action) -> some View {
        let isOn = action == .on
        return Button {
            onRun(action)
        } label: {
            Text(action.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    Capsule().fill(isOn ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.12))
                )
                .overlay(
                    Capsule().strokeBorder(isOn ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(action.title) VPN 1.1.1.1"))
        .accessibilityHint(Text("Chạy phím tắt \(VPNShortcutLauncher.shortcutName(for: action))"))
    }
}
