import SwiftUI

/// Một dòng của thẻ menu hub nổi (1.3.533). Cấu trúc cây view của dòng **cố định**: mọi phần tử luôn có mặt,
/// trạng thái chỉ đổi opacity / `disabled` / chữ — đúng bất biến "hub không vẽ lại".
///
/// ## Bố cục
/// `HStack { nút chính (icon + hai dòng chữ + badge); cụm nút video }`. Hai nút phát/dừng và đóng là **anh em**
/// của nút chính, không lồng trong `label` của nó: `Button` lồng `Button` thì chạm rơi vào nút ngoài.
///
/// ## Dòng xám
/// `isEnabled == false` ⇒ cả dòng mờ 0,4 và các nút `disabled`. Dùng `.disabled` chứ **không**
/// `allowsHitTesting(false)`: tắt hit-test thì cú chạm xuyên xuống lớp nền `menuBackdropView` và đóng luôn menu.
///
/// Cụm nút video chỉ có ở dòng `.video` — nhánh theo `kind`, là **hằng** của dòng, không đổi theo trạng thái.
/// Khi không có video, cụm này trong suốt và `disabled`, vẫn nằm trong cây view.
struct FloatingHubMenuRow: View {
    let item: FloatingHubItem
    let showsSeparator: Bool
    let onSelect: () -> Void
    let onTogglePlayback: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: item.kind.systemImage(unreadCount: item.badgeCount))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(item.kind.tint)
                        .frame(width: 28, height: 28)
                        .overlay(alignment: .topTrailing) { unreadDot }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(item.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(item.detailTone.style)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)
                }
                // Lề dọc nằm **trong** vùng chạm để cả chiều cao dòng (48pt) đều bấm được.
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!item.isEnabled)
            .accessibilityHint(Text("Mở \(item.kind.title)"))

            if item.kind == .video {
                videoControls
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .opacity(item.isEnabled ? 1 : 0.4)
        .overlay(alignment: .top) {
            Divider()
                .padding(.leading, 52)
                .opacity(showsSeparator ? 1 : 0)
        }
    }

    /// Chấm đỏ trên icon khi còn tin chưa đọc (số cụ thể nằm ở dòng phụ). Luôn trong cây view, 0 ⇒ trong suốt.
    private var unreadDot: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .offset(x: 1, y: 2)
            .opacity(item.badgeCount > 0 ? 1 : 0)
            .accessibilityHidden(true)
    }

    /// Nút phát/dừng và nút đóng — cỡ "cụm nút menu phụ" của chuẩn header (icon 14pt, khung 32×32, cách 4pt).
    private var videoControls: some View {
        HStack(spacing: 4) {
            Button(action: onTogglePlayback) {
                Image(systemName: item.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(item.isPlaying ? "Tạm dừng video" : "Phát video"))

            Button(action: onStop) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Đóng video"))
        }
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0)
        .accessibilityHidden(!item.isEnabled)
    }
}
