import SwiftUI

/// Một dòng gợi ý ở trang Danh sách của màn nghe: bìa nhỏ (`RemoteCoverImage` — chỉ giữ trong RAM, không ghi `covers/`),
/// tên, nghệ sĩ / mô tả. `isUpNext` ⇒ nhãn "Tiếp theo" (mục sẽ tự phát khi album đang nghe hết). Chữ trắng trên nền tối
/// của màn nghe như `AudioPlaylistRow`.
///
/// Có `makeAlbum` ⇒ icon "Thêm vào playlist" sau nhãn "Tiếp theo" (1.3.810, `PlaylistAlbumAddButton`): thêm **mọi bài**
/// của album gợi ý (bài lẻ ⇒ đúng bài đó). Icon là nút anh em với nút mở gợi ý, không nằm trong `label` của nó.
struct AudioSuggestionRow: View {
    let item: ExtensionItemResult
    let isUpNext: Bool
    let onSelect: () -> Void
    var makeAlbum: (() -> PlaylistAlbumInfo?)? = nil

    private var subtitle: String {
        item.description.isEmpty ? item.author : item.description
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    RemoteCoverImage(url: item.cover, referer: item.host.isEmpty ? nil : item.host, placeholderSymbol: "music.note")
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body)
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isUpNext {
                        Text("Tiếp theo")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 0.75))
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, makeAlbum == nil ? 12 : 4)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isUpNext ? "Sẽ tự phát khi hết album đang nghe" : "")

            if let makeAlbum {
                PlaylistAlbumAddButton(kind: .audio, tint: Color.white.opacity(0.6), makeAlbum: makeAlbum)
                    .padding(.trailing, 6)
            }
        }
    }
}
