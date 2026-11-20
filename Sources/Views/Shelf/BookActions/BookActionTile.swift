import SwiftUI

/// Một ô của lưới thao tác trong sheet nhấn giữ truyện (`BookActionSheet`, 1.3.1014 — anh Bửu: "sửa các option phía dưới
/// bộ sưu tập của context menu thành dạng lưới", duyệt mockup): icon màu nhấn ở trên, chữ tối đa 2 dòng ở dưới, dòng phụ
/// tuỳ chọn (dung lượng bản tải…), nền ô mờ như dòng của sheet kính (`AppGlassSheetModifier.rowFill`), bo 12.
///
/// - Ô xoá (`isDestructive`): icon + chữ đỏ.
/// - `isLoading`: vòng xoay thay icon (hàng "Thêm cả phim vào playlist" đang tải mục lục).
/// - Nằm trong một hàng `List` cùng nhiều ô khác ⇒ `.buttonStyle(.plain)` để mỗi ô nhận chạm riêng (kiểu mặc định trong
///   `List` cho cả hàng kích hoạt mọi nút).
/// - Ô cao theo hàng của lưới (`BookActionTileGrid` đề xuất chiều cao hàng) ⇒ nền kéo hết `maxHeight`.
struct BookActionTile: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    var isDestructive = false
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 22, weight: .semibold))
                    }
                }
                .frame(height: 26)
                .foregroundStyle(isDestructive ? Color.red : Color.accentColor)

                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isDestructive ? Color.red : Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppGlassSheetModifier.rowFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
}
