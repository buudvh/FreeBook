import SwiftUI

/// Một hàng của danh sách chương.
///
/// Từ 1.3.334 hàng **không** còn là một `Button` bọc cả dòng: nút tải từng chương phải là vùng chạm
/// riêng, bọc chung một `Button` thì bấm nút tải sẽ nhảy luôn sang chương đó. Vì vậy vùng chọn chương
/// là `HStack` con có `contentShape` + `onTapGesture`, còn phụ kiện bên phải đứng ngoài vùng đó.
public struct ReaderChapterRowView: View {
    public let chapter: ReaderChapterRowState
    public let isCurrent: Bool
    public let displayTitle: String
    public let theme: ReaderTheme
    public let isDownloading: Bool
    public let onSelect: () -> Void
    /// `nil` = truyện này không tải lẻ được (TXT nội bộ, hoặc chưa có trong kệ) ⇒ không hiện nút.
    public let onDownload: (() -> Void)?

    public init(
        chapter: ReaderChapterRowState,
        isCurrent: Bool,
        displayTitle: String,
        theme: ReaderTheme,
        isDownloading: Bool = false,
        onSelect: @escaping () -> Void,
        onDownload: (() -> Void)? = nil
    ) {
        self.chapter = chapter
        self.isCurrent = isCurrent
        self.displayTitle = displayTitle
        self.theme = theme
        self.isDownloading = isDownloading
        self.onSelect = onSelect
        self.onDownload = onDownload
    }

    public var body: some View {
        if chapter.isPlaceholder {
            placeholderRow
        } else {
            contentRow
        }
    }

    private var contentRow: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                Text(displayTitle)
                    .font(.body)
                    .foregroundColor(isCurrent ? .blue : theme.textColor)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            trailingAccessory
                .frame(width: 30, height: 30)
        }
        .padding(.vertical, 4)
        .listRowBackground(isCurrent ? Color.blue.opacity(0.08) : theme.backgroundColor)
    }

    /// Ba trạng thái dùng **cùng một** khung 30×30 để hàng không nhảy chiều cao khi đổi trạng thái.
    @ViewBuilder
    private var trailingAccessory: some View {
        if chapter.isCached {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
                .accessibilityLabel("Chương đã tải")
        } else if isDownloading {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(theme.textColor.opacity(0.7))
                .scaleEffect(0.7)
                .accessibilityLabel("Đang tải chương")
        } else if let onDownload {
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
                    .font(.body)
                    .foregroundColor(theme.textColor.opacity(0.55))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tải chương này")
        }
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
