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

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                titleText
                    .foregroundColor(palette.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                accessory
                Button(action: onToggleSort) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(palette.title)
                        .frame(width: 36, height: 36)
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
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var titleText: Text {
        let title = Text("Mục lục").font(.system(size: 22, weight: .bold))
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
