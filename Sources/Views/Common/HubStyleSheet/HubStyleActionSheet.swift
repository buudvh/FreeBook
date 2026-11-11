import SwiftUI

/// **Sheet hành động kiểu hub** (anh Bửu duyệt mockup 2026-11-11): cùng kiểu sheet hub / sheet điều khiển nhanh của nhạc,
/// TTS — nền kính tối theo cài đặt ngăn kéo (`DrawerGlassSheetBackground`), bo 16, cao vừa nội dung, vuốt xuống để đóng
/// (không nút chỉ để đóng). Dòng đầu tiêu đề + chú thích; các dòng `HubStyleActionSheetRow`.
///
/// Không tự trình bày: dùng `.hubStyleActionSheet(_:)` (`HubStyleActionSheetModifier`) ⇒ sheet nằm trên mọi viên thuốc
/// (`OverlaySheetPresenter`). Chạm một dòng ⇒ `onSelect` (người trình bày đóng sheet xong mới chạy `action` của dòng).
struct HubStyleActionSheet: View {
    let content: HubStyleActionSheetContent
    let onSelect: (HubStyleActionSheetContent.Item) -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            header
            ForEach(content.items) { item in
                HubStyleActionSheetRow(item: item) { onSelect(item) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .environment(\.colorScheme, .dark)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightKey.self) { newHeight in
            guard newHeight > 0, abs(newHeight - contentHeight) > 0.5 else { return }
            contentHeight = newHeight
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .appAccentTint()
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight)] : [.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(16)
        .presentationBackground { DrawerGlassSheetBackground() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(content.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let caption = content.caption, !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: - Lồng (một type chính mỗi file)

    private struct HeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}
