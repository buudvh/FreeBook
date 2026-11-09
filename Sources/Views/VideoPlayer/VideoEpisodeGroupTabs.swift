import SwiftUI

/// Hàng tab nhóm tập (mỗi dòng `section` của `toc` một tab: "Vietsub", "Thuyết minh"…) của kiểu Lưới
/// (`VideoEpisodeGridView`) và kiểu Danh sách (`VideoEpisodeListView`). Tối đa `maxEvenTabs` tab thì chia đều bề ngang,
/// nhiều hơn thì cuộn ngang để tên không bị cắt. Tab đang chọn nền trắng chữ đen; mỗi tab kèm số tập của nhóm.
///
/// Chỉ đổi `selection` — đổi tab **không** đổi tập đang phát. Nơi gọi tự ẩn hàng này khi chỉ có một nhóm.
struct VideoEpisodeGroupTabs: View {
    typealias SectionTab = VideoEpisodeGrouping.Group<VideoPlaybackSession.Episode>

    let groups: [SectionTab]
    @Binding var selection: Int

    private static let maxEvenTabs = 3

    var body: some View {
        if groups.count <= Self.maxEvenTabs {
            HStack(spacing: 4) {
                ForEach(groups) { group in
                    tab(group, fillsWidth: true)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(groups) { group in
                        tab(group, fillsWidth: false)
                    }
                }
            }
        }
    }

    private func tab(_ group: SectionTab, fillsWidth: Bool) -> some View {
        let isSelected = group.id == selection
        let label = Self.label(of: group)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection = group.id }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .lineLimit(1)
                Text("\(group.items.count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .opacity(0.55)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(group.items.count) tập")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Nhóm đứng trước section đầu tiên không có tên ⇒ "Tập".
    static func label(of group: SectionTab) -> String {
        group.title.isEmpty ? "Tập" : group.title
    }
}
