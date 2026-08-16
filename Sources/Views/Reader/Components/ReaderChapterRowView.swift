import SwiftUI

public struct ReaderChapterRowView: View {
    public let chapter: ReaderChapterRowState
    public let isCurrent: Bool
    public let displayTitle: String
    public let theme: ReaderTheme
    public let onSelect: () -> Void

    public init(
        chapter: ReaderChapterRowState,
        isCurrent: Bool,
        displayTitle: String,
        theme: ReaderTheme,
        onSelect: @escaping () -> Void
    ) {
        self.chapter = chapter
        self.isCurrent = isCurrent
        self.displayTitle = displayTitle
        self.theme = theme
        self.onSelect = onSelect
    }

    public var body: some View {
        if chapter.isPlaceholder {
            placeholderRow
        } else {
            contentButton
        }
    }

    private var contentButton: some View {
        Button(action: onSelect) {
            HStack {
                Text(displayTitle)
                    .font(.body)
                    .foregroundColor(isCurrent ? .blue : theme.textColor)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(2)
                Spacer()
                if chapter.isCached {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(isCurrent ? Color.blue.opacity(0.08) : theme.backgroundColor)
    }

    private var placeholderRow: some View {
        HStack(spacing: 8) {
            SkeletonView(width: placeholderWidth, height: 14, color: theme.textColor.opacity(0.18))
            Spacer()
            SkeletonView(width: 14, height: 14, color: theme.textColor.opacity(0.18))
        }
        .padding(.vertical, 4)
        .listRowBackground(theme.backgroundColor)
        .accessibilityLabel("Đang tải chương...")
    }

    private var placeholderWidth: CGFloat {
        let widths: [CGFloat] = [150, 130, 160, 120, 140, 110]
        return widths[chapter.index % widths.count]
    }
}
