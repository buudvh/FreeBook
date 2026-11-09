import SwiftUI

/// Một hàng của trang Danh sách phát: số thứ tự (vị trí trong danh sách bài), tên bài + nghệ sĩ. Bài đang phát: chữ màu
/// nhấn, nền nhấn mờ, icon loa.
struct AudioPlaylistRow: View {
    let position: Int
    let title: String
    let artist: String
    let isCurrent: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text("\(position)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.5)))
                    .frame(minWidth: 28, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white))
                        .lineLimit(1)
                    if !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isCurrent ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
