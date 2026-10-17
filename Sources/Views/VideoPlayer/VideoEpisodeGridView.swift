import SwiftUI

/// Lưới tập phim. Dòng `section` của `toc` đã bị bỏ ở tầng `ExtensionManager.toc` nên mọi ô ở đây đều phát được.
/// Mỗi ô gắn `.id(episode.index)` để màn cha cuộn tới tập đang xem.
struct VideoEpisodeGridView: View {
    let episodes: [VideoPlayerController.Episode]
    let currentIndex: Int
    let onSelect: (VideoPlayerController.Episode) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Danh sách tập (\(episodes.count))")
                .font(.headline)
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(episodes) { episode in
                    cell(for: episode)
                        .id(episode.index)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func cell(for episode: VideoPlayerController.Episode) -> some View {
        let isCurrent = episode.index == currentIndex
        return Button {
            onSelect(episode)
        } label: {
            HStack(spacing: 4) {
                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(episode.title.isEmpty ? "Tập \(episode.index + 1)" : episode.title)
                    .font(.footnote.weight(isCurrent ? .bold : .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isCurrent ? Color.black : Color.white)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrent ? Color.white : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}
