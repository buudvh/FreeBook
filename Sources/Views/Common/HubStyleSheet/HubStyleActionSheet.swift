import SwiftUI

/// **Sheet hành động kiểu hub** (anh Bửu duyệt mockup 2026-11-11): cùng kiểu sheet hub / sheet điều khiển nhanh của nhạc,
/// TTS — nền kính tối theo cài đặt ngăn kéo (`DrawerGlassSheetBackground`), bo 16, cao vừa nội dung, vuốt xuống để đóng
/// (không nút chỉ để đóng). Dòng đầu tiêu đề + chú thích; các dòng `HubStyleActionSheetRow`.
///
/// - Dòng thường: chạm ⇒ `close(then: action)` — người trình bày đóng sheet xong mới chạy việc.
/// - Dòng có `page`: chạm ⇒ **chuyển trang ngay trong sheet** (khuôn trang "Tác vụ AI" của sheet hub): sheet lên nấc
///   large, header có tiêu đề giữa + nút ‹ (`sheetPageBack`) về trang chính (về lại chiều cao vừa nội dung). Nền danh sách
///   của trang ẩn (`scrollContentBackground(.hidden)`) để thấy kính của sheet.
///
/// Không tự trình bày: dùng `.hubStyleActionSheet(_:)` (`HubStyleActionSheetModifier`) ⇒ sheet nằm trên mọi viên thuốc
/// (`OverlaySheetPresenter`, cửa sổ nhận bàn phím trong lúc có sheet nên trang con có ô nhập được).
struct HubStyleActionSheet: View {
    let content: HubStyleActionSheetContent
    let close: HubStyleActionSheetContent.CloseSheet

    @State private var contentHeight: CGFloat = 0
    @State private var openPageId: String?

    var body: some View {
        Group {
            if let page = openPage {
                NavigationStack {
                    page.content(close)
                        .scrollContentBackground(.hidden)
                        .pageTitle(page.title, style: .centered)
                        .sheetPageBackButton()
                }
                .environment(\.sheetPageBack, {
                    withAnimation(.easeInOut(duration: 0.25)) { openPageId = nil }
                })
            } else {
                mainPage
            }
        }
        .environment(\.colorScheme, .dark)
        .appAccentTint()
        .presentationDetents(openPage != nil ? [.large] : mainDetents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(16)
        .presentationBackground { DrawerGlassSheetBackground() }
    }

    private var openPage: HubStyleActionSheetContent.Page? {
        guard let openPageId else { return nil }
        return content.items.first(where: { $0.id == openPageId })?.page
    }

    /// Một nấc cao đúng nội dung (`.medium` trong lúc chờ đo lần đầu).
    private var mainDetents: Set<PresentationDetent> {
        contentHeight > 0 ? [.height(contentHeight)] : [.medium]
    }

    private var mainPage: some View {
        VStack(spacing: 8) {
            header
            ForEach(content.items) { item in
                HubStyleActionSheetRow(item: item) { select(item) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
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
    }

    private func select(_ item: HubStyleActionSheetContent.Item) {
        if item.page != nil {
            withAnimation(.easeInOut(duration: 0.25)) { openPageId = item.id }
        } else {
            close(item.action)
        }
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
