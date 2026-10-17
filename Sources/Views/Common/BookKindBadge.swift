import SwiftUI

/// Badge loại nội dung (truyện chữ / truyện tranh / video).
///
/// - Góc bìa sách ở Kệ / bộ sưu tập (`ShelfBookRowView`): chỉ icon, và **chỉ** với truyện tranh/video — truyện
///   chữ là mặc định, gắn badge chỉ thêm nhiễu (`hidesText = true`).
/// - Dòng tiện ích ở bảng chọn nguồn Khám phá: icon + nhãn cho mọi loại (`showsLabel = true`, `hidesText = false`).
struct BookKindBadge: View {
    let kind: ExtensionContentKind
    var showsLabel = false
    var hidesText = true

    var body: some View {
        if kind != .unsupported && (kind.isMedia || !hidesText) {
            HStack(spacing: 3) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: showsLabel ? 9 : 10, weight: .semibold))
                if showsLabel {
                    Text(kind.label)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, showsLabel ? 6 : 4)
            .padding(.vertical, showsLabel ? 2 : 3)
            .foregroundColor(.white)
            .background(tint.opacity(showsLabel ? 0.35 : 0.85))
            .cornerRadius(4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind.label)
        }
    }

    private var tint: Color {
        switch kind {
        case .comic: return .purple
        case .video: return .red
        case .text, .unsupported: return .gray
        }
    }
}
