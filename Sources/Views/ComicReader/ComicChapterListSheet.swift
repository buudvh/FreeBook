import SwiftUI

/// Mục lục của màn đọc comic — cùng bố cục với mục lục truyện chữ (`ReaderChapterListView`): header bìa + tên + nguồn
/// + hàng nút (`ComicChapterListSheet+Header.swift`), ô tìm chương, danh sách chương. `ComicReaderView` trình bày bằng
/// sheet gốc (detents 0.88/large, có thanh kéo) nên không có thanh tiêu đề hay nút đóng: kéo xuống để đóng.
///
/// - Màn comic luôn tối (`preferredColorScheme(.dark)`), không có `ReaderTheme` riêng ⇒ dùng màu của `ReaderTheme.dark`.
/// - `book` (nếu có) dùng cho nút **tải ảnh offline** (`TaskOptionsSheet`, y như nhấn-giữ một truyện ở Kệ/Lịch sử) và
///   nút **thêm/bỏ kệ** (`ShelfToggleFlowModifier`). Sách chưa có trong thư viện thì không có hàng `Book` nên hai nút
///   ẩn; bìa/tên/tác giả khi đó lấy từ `launch`.
/// - Thứ tự sắp xếp là `Binding` từ `ComicReaderView`: giữ suốt phiên đọc, không lưu đĩa.
/// - Đang tìm hoặc đang xếp giảm dần ⇒ ẩn dòng tiêu đề nhóm (`isSection`): nhãn nhóm chỉ có nghĩa khi đứng ngay trên
///   các chương của nó theo thứ tự gốc.
@MainActor
struct ComicChapterListSheet: View {
    /// Màu nền/chữ của sheet — `ComicReaderView` dùng cùng màu cho `presentationBackground`.
    static var theme: ReaderTheme { .dark }

    let chapters: [ComicChapterEntry]
    let currentIndex: Int
    let downloadedIndexes: Set<Int>
    let isTranslationEnabled: Bool
    let book: Book?
    let launch: BookContentLaunch
    @Binding var isAscending: Bool
    let onSelect: (Int) -> Void
    /// Chạm bìa (kèm URL chi tiết): màn đọc đóng sheet này rồi đẩy Chi tiết truyện vào `NavigationStack` của nó.
    var onOpenBookDetail: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) var modelContext
    @State private var searchQuery = ""
    @State var showingDownloadOptions = false
    @State var isConfirmingShelfRemoval = false
    @State var collectionPickerBook: Book? = nil

    /// Màu panel Mục lục — cùng bảng màu nền Tối của mục lục truyện chữ.
    static var palette: ChapterTOCPalette { .reader(theme) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if chapters.isEmpty {
                ContentUnavailableView(
                    "Chưa có mục lục",
                    systemImage: "list.bullet",
                    description: Text("Mở trang chi tiết truyện để tải mục lục.")
                )
                .frame(maxHeight: .infinity)
            } else {
                // Panel Mục lục dùng chung với truyện chữ / tab Mục lục của Chi tiết.
                VStack(spacing: 0) {
                    ChapterTOCPanelHeader(
                        chapterCount: readableChapterCount,
                        searchText: $searchQuery,
                        isAscending: isAscending,
                        palette: Self.palette,
                        onToggleSort: { isAscending.toggle() }
                    )
                    chapterList
                }
                .chapterTOCPanel(Self.palette)
            }
        }
        .background(Self.theme.backgroundColor.ignoresSafeArea())
        .sheet(isPresented: $showingDownloadOptions) {
            if let book {
                TaskOptionsSheet(book: book, taskType: .download)
            }
        }
        .shelfToggleFlow(
            book: book,
            displayTitle: metadataTitle,
            isConfirmingRemoval: $isConfirmingShelfRemoval,
            collectionPickerBook: $collectionPickerBook
        )
    }

    // MARK: - Danh sách

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hàng đang hiện: lọc theo tên **đang hiển thị** (đã dịch nếu bật dịch), không phân biệt hoa thường, rồi xếp theo
    /// `isAscending`. Dòng tiêu đề nhóm chỉ giữ khi không tìm và xếp tăng dần.
    private var visibleChapters: [ComicChapterEntry] {
        let query = trimmedQuery
        let showsSections = query.isEmpty && isAscending
        let rows = chapters.filter { chapter in
            if chapter.isSection { return showsSections }
            guard !query.isEmpty else { return true }
            return chapter.displayTitle(translated: isTranslationEnabled).localizedCaseInsensitiveContains(query)
        }
        return isAscending ? rows : Array(rows.reversed())
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            List(visibleChapters, id: \.index) { chapter in
                Group {
                    if chapter.isSection {
                        sectionHeader(for: chapter)
                    } else {
                        row(for: chapter)
                    }
                }
                .id(chapter.index)
            }
            .listStyle(.plain)
            // Nằm trong panel Mục lục: nền trong suốt để thấy nền panel (hàng tự đặt nền + màu vạch).
            .scrollContentBackground(.hidden)
            .onAppear {
                // Đợi List dựng xong rồi mới cuộn tới chương đang đọc.
                DispatchQueue.main.async {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }

    /// Dòng tiêu đề nhóm tập (`isSection`): chỉ là nhãn, không chạm được.
    private func sectionHeader(for chapter: ComicChapterEntry) -> some View {
        Text(chapter.displayTitle(translated: isTranslationEnabled))
            .font(.subheadline.weight(.bold))
            .foregroundColor(Self.theme.textColor.opacity(0.6))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .listRowBackground(Color.white.opacity(0.05))
            .listRowSeparatorTint(Self.palette.divider)
            .accessibilityAddTraits(.isHeader)
    }

    /// Cùng kiểu `ReaderChapterRowView`: đang đọc = chữ trắng đậm + nền mờ; đã đọc (index logic nhỏ hơn) = mờ
    /// 0.4; đã tải offline = icon xanh trong khung 30×30 cố định để hàng không đổi chiều cao.
    private func row(for chapter: ComicChapterEntry) -> some View {
        let isCurrent = chapter.index == currentIndex
        let isRead = chapter.index < currentIndex
        let theme = Self.theme
        let palette = Self.palette
        return Button {
            onSelect(chapter.index)
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Text(chapter.displayTitle(translated: isTranslationEnabled))
                    .font(.body)
                    .foregroundColor(isCurrent ? palette.title : (isRead ? theme.textColor.opacity(0.4) : theme.textColor))
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)

                Color.clear
                    .frame(width: 30, height: 30)
                    .overlay {
                        if downloadedIndexes.contains(chapter.index) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                                .accessibilityLabel("Đã tải offline")
                        }
                    }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? palette.currentRowFill : Color.clear)
        .listRowSeparatorTint(palette.divider)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
