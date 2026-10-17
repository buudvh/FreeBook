import SwiftUI

/// Lưới tập phim **nhóm theo section**: dòng `type: "section"` của `toc` (ext nhiều server) là tiêu đề nhóm, không chọn
/// được; các tập sau nó thuộc nhóm đó tới section kế. Tập đứng trước section đầu tiên nằm trong nhóm không tiêu đề.
///
/// Ô tập gắn `.id(episode.index)` (Int) để màn cha cuộn tới tập đang xem; tiêu đề nhóm dùng id dạng chuỗi
/// `"section-<index>"` nên không đụng id của ô tập.
struct VideoEpisodeGridView: View {
    let episodes: [VideoPlaybackSession.Episode]
    let currentIndex: Int
    let onSelect: (VideoPlaybackSession.Episode) -> Void

    private struct EpisodeGroup: Identifiable {
        /// Chỉ số của dòng section; nhóm không tiêu đề dùng -1 (chỉ số thật luôn >= 0).
        let id: Int
        let header: VideoPlaybackSession.Episode?
        var items: [VideoPlaybackSession.Episode]
    }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        let groups = makeGroups()
        VStack(alignment: .leading, spacing: 12) {
            Text("Danh sách tập (\(episodes.filter { !$0.isSection }.count))")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    if let header = group.header {
                        sectionHeader(header)
                    }
                    if !group.items.isEmpty {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(group.items) { episode in
                                cell(for: episode)
                                    .id(episode.index)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func makeGroups() -> [EpisodeGroup] {
        var groups: [EpisodeGroup] = []
        for episode in episodes {
            if episode.isSection {
                groups.append(EpisodeGroup(id: episode.index, header: episode, items: []))
            } else if groups.isEmpty {
                groups.append(EpisodeGroup(id: -1, header: nil, items: [episode]))
            } else {
                groups[groups.count - 1].items.append(episode)
            }
        }
        return groups
    }

    private func sectionHeader(_ section: VideoPlaybackSession.Episode) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.6))
                .frame(width: 3, height: 14)
            Text(section.title.isEmpty ? "Nhóm tập" : section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
        }
        .padding(.top, 4)
        .id("section-\(section.index)")
        .accessibilityAddTraits(.isHeader)
    }

    private func cell(for episode: VideoPlaybackSession.Episode) -> some View {
        let isCurrent = episode.index == currentIndex
        return Button {
            onSelect(episode)
        } label: {
            HStack(spacing: 4) {
                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(episode.displayTitle)
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
