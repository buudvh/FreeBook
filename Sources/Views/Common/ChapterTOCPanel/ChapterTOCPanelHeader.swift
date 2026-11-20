import SwiftUI

/// Đầu panel Mục lục (dùng chung Chi tiết / Reader / comic): hàng "Mục lục (N chương)" + nút đảo thứ tự ↓↑, dưới là
/// ô tìm `ChapterTOCSearchField` (khi có `searchText`). `accessory` (vd nút tải lại lỗi của Chi tiết) đứng trước nút
/// sắp xếp. Tự đệm theo lề trong của panel — đặt thẳng trong `.chapterTOCPanel(_:)`, phía trên danh sách.
struct ChapterTOCPanelHeader<Accessory: View>: View {
    /// 0 = chưa có mục lục ⇒ chỉ hiện "Mục lục".
    let chapterCount: Int
    let noun: String
    let searchText: Binding<String>?
    let isAscending: Bool
    let palette: ChapterTOCPalette
    let onToggleSort: () -> Void
    let accessory: Accessory

    init(
        chapterCount: Int,
        noun: String = "chương",
        searchText: Binding<String>?,
        isAscending: Bool,
        palette: ChapterTOCPalette,
        onToggleSort: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.chapterCount = chapterCount
        self.noun = noun
        self.searchText = searchText
        self.isAscending = isAscending
        self.palette = palette
        self.onToggleSort = onToggleSort
        self.accessory = accessory()
    }

    /// `ChapterTOCSearchField` tự đệm phải 6pt (bù lề phải hẹp của các màn dùng chung nó). Panel này đã lề hai bên bằng
    /// nhau (1.3.1017) ⇒ kéo ô tìm ra lại đúng chừng đó để mép phải ô thẳng nút ↓↑. Bỏ khoản đệm trong ô tìm thì bỏ cả cái này.
    private static var searchFieldTrailingPad: CGFloat { 6 }

    var body: some View {
        VStack(spacing: 10) {
            // Tiêu đề không co chữ (lưới header chung): dài thì cắt đuôi.
            HStack(spacing: 6) {
                titleText
                    .foregroundColor(palette.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                accessory
                // Nút ngoài cùng: icon canh phải trong khung ⇒ chạm lề như các header khác.
                Button(action: onToggleSort) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                        .foregroundColor(palette.title)
                        .frame(width: HeaderMetrics.iconFrameWidth, height: 36, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isAscending ? "Sắp xếp chương giảm dần" : "Sắp xếp chương tăng dần")
            }

            if let searchText {
                ChapterTOCSearchField(
                    text: searchText,
                    placeholder: chapterCount > 0 ? "Tìm kiếm \(chapterCount) \(noun)" : "Tìm kiếm \(noun)",
                    palette: palette
                )
                .padding(.trailing, -Self.searchFieldTrailingPad)
            }
        }
        .padding(.horizontal, HeaderMetrics.horizontalMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var titleText: Text {
        let title = Text("Mục lục").font(.system(size: HeaderMetrics.rowTitleFontSize, weight: .bold))
        guard chapterCount > 0 else { return title }
        return title + Text("  (\(chapterCount) \(noun))").font(.system(size: 17, weight: .medium))
    }
}

extension ChapterTOCPanelHeader where Accessory == EmptyView {
    init(
        chapterCount: Int,
        noun: String = "chương",
        searchText: Binding<String>?,
        isAscending: Bool,
        palette: ChapterTOCPalette,
        onToggleSort: @escaping () -> Void
    ) {
        self.init(
            chapterCount: chapterCount,
            noun: noun,
            searchText: searchText,
            isAscending: isAscending,
            palette: palette,
            onToggleSort: onToggleSort,
            accessory: { EmptyView() }
        )
    }
}
