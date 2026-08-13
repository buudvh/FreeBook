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
        Button(action: onSelect) {
            HStack {
                Text(displayTitle)
                    .font(.body)
                    .foregroundColor(isCurrent ? .blue : theme.textColor)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(2)
                Spacer()
                if !chapter.isPlaceholder && chapter.isCached {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(chapter.isPlaceholder)
        .listRowBackground(isCurrent ? Color.blue.opacity(0.08) : theme.backgroundColor)
    }
}
