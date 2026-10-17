import SwiftUI

/// Section `chip`: một hàng chip chữ cuộn ngang (thường là thể loại/thẻ, chạm mở action `list` của item).
/// Kiểu chip giống chip tab chưa chọn ở thanh danh mục của `DiscoveryView`.
struct ExploreChipRowView: View {
    let items: [ExploreItem]
    let context: ExploreRenderContext

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        context.onSelect(item)
                    } label: {
                        Text(context.display(item.name))
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                            .overlay {
                                Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
