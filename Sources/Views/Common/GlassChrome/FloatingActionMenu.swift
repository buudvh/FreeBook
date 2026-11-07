import SwiftUI

/// Nút "+" nổi dạng **menu xổ** (kiểu FAB của Chi tiết truyện): bấm nút tròn ⇒ các pill hiện phía trên, `items` xếp từ
/// trên xuống — pill cuối nằm sát nút (Home luôn đặt cuối). Nút xoay thành "×" khi mở; bấm pill ⇒ đóng menu rồi chạy
/// hành động. Dùng chung cho nút "+" của màn danh sách (`FloatingAddButton` khi trang có Home) và FAB Chi tiết.
///
/// - Pill vẽ bằng `overlay` của nút tròn ⇒ khung nút giữ nguyên 52pt: `.floatingAddButton` vẫn chỉ chiếm `safeAreaInset`
///   52 + 12, danh sách không nhảy khi mở menu.
/// - Pill và nút đều nền kính `FloatingGlassBackground` (theo Cài đặt › Giao diện). Chữ có bóng mảnh để còn đọc được khi
///   kính gần trong suốt.
/// - Chuyển cảnh chỉ `scale` — **không** `.opacity`: alpha < 1 trên lớp cha tắt nhoè của kính (lỗi 1.3.640, ghi ở
///   `FloatingGlassBackground`).
struct FloatingActionMenu: View {
    private static let animation = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Nhãn trợ năng của nút tròn khi menu đang đóng.
    let accessibilityLabel: String
    let items: [FloatingActionItem]

    @State private var isExpanded = false

    var body: some View {
        FloatingRoundButton(
            systemImage: "plus",
            accessibilityLabel: isExpanded ? "Đóng menu" : accessibilityLabel,
            iconRotation: .degrees(isExpanded ? 135 : 0)
        ) {
            withAnimation(Self.animation) { isExpanded.toggle() }
        }
        .overlay(alignment: .bottomTrailing) {
            if isExpanded {
                VStack(alignment: .trailing, spacing: 10) {
                    ForEach(items) { item in
                        pill(item)
                    }
                }
                .fixedSize()
                .padding(.bottom, FloatingRoundButton.size + 10)
                .transition(.scale(scale: 0.4, anchor: .bottomTrailing))
            }
        }
        .onDisappear { isExpanded = false }
    }

    private func pill(_ item: FloatingActionItem) -> some View {
        Button {
            withAnimation(Self.animation) { isExpanded = false }
            item.action()
        } label: {
            HStack(spacing: 6) {
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .lineLimit(1)
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.highlight ?? Color.white)
            }
            .foregroundStyle(Color.white)
            .shadow(color: .black.opacity(0.45), radius: 1.5, y: 0.5)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background {
                FloatingGlassBackground(outline: item.highlight ?? .white, shape: AnyShape(Capsule()))
            }
            .overlay {
                if let highlight = item.highlight {
                    Capsule().stroke(highlight.opacity(0.85), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }
}
