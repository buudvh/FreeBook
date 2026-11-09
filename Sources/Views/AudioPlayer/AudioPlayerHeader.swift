import SwiftUI

/// Header của màn nghe: trái ⌄ (thu nhỏ — đóng màn, nhạc vẫn phát), giữa "Phát từ album" + tên album, phải `…` (ngăn kéo
/// tuỳ chọn). Icon 17pt nửa đậm, vùng chạm 44×44.
struct AudioPlayerHeader: View {
    let albumTitle: String
    let onMinimize: () -> Void
    let onMenu: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            iconButton(systemImage: "chevron.down", label: "Thu nhỏ màn nghe", action: onMinimize)
            VStack(spacing: 1) {
                Text("Phát từ album")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                Text(albumTitle.isEmpty ? "Album" : albumTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .accessibilityElement(children: .combine)
            iconButton(systemImage: "ellipsis", label: "Tuỳ chọn trình nghe", action: onMenu)
        }
        .padding(.horizontal, 6)
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    private func iconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
