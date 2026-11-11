import SwiftUI

/// Một hàng của mục lục truyện tranh (1.3.843): dòng nhóm **hoặc** chương — một kiểu view cho mọi phần tử để `List` chỉ
/// dựng các hàng đang hiện. Bọc `if dòng nhóm … else hàng chương …` ngay trong `ForEach` (như trước) có thể buộc `List`
/// dựng mọi hàng để đếm — mục lục Reader cũng giữ đúng một kiểu hàng (`ReaderChapterListView+List`).
///
/// Nền hàng và màu vạch gắn ở chỗ dựng `List` (`ComicChapterListSheet`), không ở đây.
struct ComicChapterListRow: View {
    let chapter: ComicChapterEntry
    let isTranslationEnabled: Bool
    let currentIndex: Int
    let isDownloaded: Bool
    let numbering: ChapterOrdinalNumbering?
    let onSelect: (Int) -> Void

    private static var theme: ReaderTheme { ComicChapterListSheet.theme }
    private static var palette: ChapterTOCPalette { ComicChapterListSheet.palette }

    var body: some View {
        if chapter.isSection {
            sectionHeader
        } else {
            chapterRow
        }
    }

    /// Dòng tiêu đề nhóm tập: chỉ là nhãn, không chạm được.
    private var sectionHeader: some View {
        Text(chapter.displayTitle(translated: isTranslationEnabled))
            .font(.subheadline.weight(.bold))
            .foregroundColor(Self.theme.textColor.opacity(0.6))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }

    /// Cùng kiểu `ReaderChapterRowView`: đang đọc = chữ đậm + nền mờ; đã đọc (index logic nhỏ hơn) = mờ 0.4; đã tải offline
    /// = icon xanh trong khung 30×30 cố định để hàng không đổi chiều cao.
    private var chapterRow: some View {
        let isCurrent = chapter.index == currentIndex
        let isRead = chapter.index < currentIndex
        let theme = Self.theme
        let palette = Self.palette
        return Button {
            onSelect(chapter.index)
        } label: {
            HStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let numbering {
                        ChapterOrdinalLabel(
                            ordinal: numbering.ordinal(forIndex: chapter.index),
                            digits: numbering.digits,
                            palette: palette,
                            isCurrent: isCurrent,
                            isRead: isRead
                        )
                    }
                    Text(chapter.displayTitle(translated: isTranslationEnabled))
                        .font(.body)
                        .foregroundColor(isCurrent ? palette.title : (isRead ? theme.textColor.opacity(0.4) : theme.textColor))
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)

                Color.clear
                    .frame(width: 30, height: 30)
                    .overlay {
                        if isDownloaded {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                                .accessibilityLabel("Đã tải offline")
                        }
                    }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
