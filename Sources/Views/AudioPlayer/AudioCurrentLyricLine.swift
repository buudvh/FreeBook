import SwiftUI

/// Một dòng lời đang hát dưới tên bài ở trang Đĩa (chỉ khi lời có mốc giờ và đã tới dòng đầu). Luôn giữ chỗ một dòng để
/// bố cục không nhảy khi lời xuất hiện / biến mất. Tách view: chỉ đọc `currentLyricLineIndex` (đổi theo dòng, không theo
/// tick).
struct AudioCurrentLyricLine: View {
    private var session: AudioPlaybackSession { .shared }

    private var text: String {
        guard let lyrics = session.lyrics, lyrics.isSynced,
              let index = session.currentLyricLineIndex, lyrics.lines.indices.contains(index) else { return "" }
        return lyrics.lines[index].text
    }

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.tint)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: text)
            .accessibilityHidden(text.isEmpty)
    }
}
