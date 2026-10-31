import SwiftUI

/// Một hàng chương trong panel Mục lục của tab Chi tiết — dùng chung cho cả ba nguồn mục lục của `BookDetailTOCView`
/// (`StoredChapterSnapshot`, `Chapter`, `ChapterResult`): vạch ngăn ở **trên** (hàng đầu nối với ô tìm), chữ `.body` tối
/// đa 2 dòng; đang đọc = đậm + nền mờ, đã đọc = mờ 0.4, đã tải = icon xanh.
struct BookDetailTOCRow: View {
    let title: String
    let isCurrent: Bool
    let isRead: Bool
    let isCached: Bool
    let palette: ChapterTOCPalette
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(palette.divider)
                    .frame(height: 0.5)
                    .padding(.horizontal, 8)
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundColor(isCurrent ? palette.title : (isRead ? palette.text.opacity(0.4) : palette.text))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if isCached {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                            .accessibilityLabel("Chương đã tải")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 11)
                .background(
                    isCurrent ? palette.currentRowFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
