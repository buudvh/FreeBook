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
/// - Hàng đang hiện + số thứ tự dựng **một lần** mỗi khi mục lục / ô tìm / thứ tự / công tắc đổi (`ComicChapterListRows`,
///   mục lục dài thì ngoài main) chứ không trong mỗi lượt vẽ; dòng nhóm luôn giữ, kể cả khi tìm hay xếp giảm dần (1.3.843).
///   Mỗi phần tử một kiểu hàng (`ComicChapterListRow`). `ComicReaderView` bọc sheet trong `ComicChapterListHost`
///   (`.equatable()`) để màn đọc vẽ lại không kéo mục lục tính lại.
/// - Bộ dịch là tiện ích dịch: hàng / dòng nhóm / tên truyện ở đầu đọc `extensionText` trong `body` của chính nó ⇒ chỉ tên
///   đang hiện xin dịch, theo lô. Ô tìm vẫn khớp tên QT, tên gốc, tên đã chuyển (dựng hàng ngoài main, không thấy store).
@MainActor
struct ComicChapterListSheet: View {
    /// Màu nền/chữ của sheet — `ComicReaderView` dùng cùng màu cho `presentationBackground`.
    static var theme: ReaderTheme { .dark }

    let chapters: [ComicChapterEntry]
    let currentIndex: Int
    let downloadedIndexes: Set<Int>
    let isTranslationEnabled: Bool
    let extensionText: ComicExtensionTextTranslation
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
    @State var collectionPickerBook: Book? = nil
    /// Công tắc "Hiện số thứ tự chương" — đọc một lần ở danh sách, hàng chỉ nhận số + bề rộng cột.
    @AppStorage(ChapterOrdinalNumbering.showsOrdinalKey)
    private var showsChapterOrdinal = ChapterOrdinalNumbering.showsOrdinalDefault
    @State private var rows: [ComicChapterEntry] = []
    @State private var numbering: ChapterOrdinalNumbering?
    @State private var hasBuiltRows = false
    @State private var isBuildingRows = false
    @State private var didScrollToCurrent = false
    /// Lúc sheet được dựng (≈ lúc bấm ☰) — cho log thời gian mở `📚 [ComicTOC]`.
    @State private var openedAt = Date()

    /// Đầu vào của lượt dựng hàng; đổi ⇒ `.task(id:)` dựng lại.
    private struct RowsKey: Equatable {
        let chapters: [ComicChapterEntry]
        let query: String
        let ascending: Bool
        let translated: Bool
        let numbered: Bool
    }

    /// Mục lục ngắn hơn ngưỡng dựng ngay trên main (tức thì); dài hơn thì ngoài main kèm vòng xoay.
    private static let backgroundBuildThreshold = 400

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
            Group {
                if let book {
                    TaskOptionsSheet(book: book, taskType: .download)
                }
            }
            .appGlassSheet()
        }
        .shelfToggleFlow(collectionPickerBook: $collectionPickerBook)
    }

    // MARK: - Danh sách

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rowsKey: RowsKey {
        RowsKey(
            chapters: chapters,
            query: trimmedQuery,
            ascending: isAscending,
            translated: isTranslationEnabled,
            numbered: showsChapterOrdinal
        )
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            List(rows, id: \.index) { chapter in
                ComicChapterListRow(
                    chapter: chapter,
                    isTranslationEnabled: isTranslationEnabled,
                    extensionText: extensionText,
                    currentIndex: currentIndex,
                    isDownloaded: downloadedIndexes.contains(chapter.index),
                    numbering: numbering,
                    onSelect: { index in
                        onSelect(index)
                        dismiss()
                    }
                )
                .id(chapter.index)
                .listRowBackground(rowBackground(for: chapter))
                .listRowSeparatorTint(Self.palette.divider)
            }
            .listStyle(.plain)
            // Nằm trong panel Mục lục: nền trong suốt để thấy nền panel (hàng tự đặt nền + màu vạch).
            .scrollContentBackground(.hidden)
            .overlay {
                if isBuildingRows && !hasBuiltRows {
                    ProgressView()
                        .tint(Self.theme.textColor)
                }
            }
            .task(id: rowsKey) { await rebuildRows() }
            .onChange(of: hasBuiltRows) { _, built in
                // Lần đầu có hàng mới cuộn tới chương đang đọc (đợi `List` dựng xong).
                guard built, !didScrollToCurrent else { return }
                didScrollToCurrent = true
                DispatchQueue.main.async {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }

    private func rowBackground(for chapter: ComicChapterEntry) -> Color {
        if chapter.isSection { return Color.white.opacity(0.05) }
        return chapter.index == currentIndex ? Self.palette.currentRowFill : Color.clear
    }

    /// Dựng lại hàng theo `rowsKey`; lượt mới (gõ tiếp, đảo thứ tự) huỷ lượt cũ nhờ `.task(id:)`.
    private func rebuildRows() async {
        let key = rowsKey
        let result: ComicChapterListRows.Result
        if key.chapters.count <= Self.backgroundBuildThreshold {
            result = ComicChapterListRows.build(
                chapters: key.chapters,
                query: key.query,
                ascending: key.ascending,
                translated: key.translated,
                numbered: key.numbered
            )
        } else {
            isBuildingRows = true
            let worker = Task.detached(priority: .userInitiated) {
                ComicChapterListRows.build(
                    chapters: key.chapters,
                    query: key.query,
                    ascending: key.ascending,
                    translated: key.translated,
                    numbered: key.numbered
                )
            }
            result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            isBuildingRows = false
        }
        guard !Task.isCancelled else { return }
        rows = result.rows
        numbering = result.numbering
        if !hasBuiltRows {
            hasBuiltRows = true
            let elapsed = Int(Date().timeIntervalSince(openedAt) * 1000)
            AppLogger.shared.log("📚 [ComicTOC] Mở mục lục \(key.chapters.count) dòng (\(result.rows.count) hiện): có hàng sau \(elapsed) ms")
        }
    }
}
