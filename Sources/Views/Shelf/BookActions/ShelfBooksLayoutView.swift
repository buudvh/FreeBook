import SwiftUI

/// Khung danh sách truyện phía kệ (tab Kệ sách, tab Lịch sử, chi tiết Bộ sưu tập, kết quả lưới của Tìm trên kệ),
/// dựng theo kiểu hiển thị của `scope` trong `BookListLayoutPreferences` (đọc trong `body` ⇒ sheet "Kiểu hiển thị"
/// ghi xong là vẽ lại ngay).
///
/// Hai nhánh tách hẳn nhau:
/// - `.list`: `List` `.plain` + `Section` + `ShelfBookRowView` dạng panel bo góc (`bookListPanelRow`, không vạch
///   ngăn), sentinel `ProgressView` cuối danh sách; cỡ dòng theo `BookListLayout.rowSize`.
/// - `.grid` / `.coverOnly`: `ScrollView` + `LazyVGrid` N cột với `ShelfBookGridCardView`. **`LazyVGrid` tuyệt đối
///   không lồng trong `List`** (crash `EXC_BREAKPOINT` ở 1.3.269, xem `CollectionsTabView`).
///
/// Mọi hàng/thẻ dùng `onTapGesture` + `onLongPressGesture` chứ **không** bọc `Button`: bọc Button thì nhả tay sau khi
/// giữ vẫn kích hoạt action, mở luôn cả Reader. View này chỉ phát sự kiện; rung, `markSeen`, mở Reader/sheet là
/// việc của nơi dùng (mỗi màn có luật riêng — Lịch sử không `markSeen`).
@MainActor
struct ShelfBooksLayoutView: View {
    /// Tiêu đề một nhóm (`ShelfSectionHeaderView`).
    struct Header {
        let title: String
        let icon: String
        let color: Color
        let count: Int
    }

    /// Một nhóm truyện. `header == nil` ⇒ dựng thẳng các hàng, không bọc `Section` (kệ chưa ghim truyện nào, kết
    /// quả Tìm trên kệ) để không có tiêu đề nhóm lơ lửng một mình.
    struct BookGroup: Identifiable {
        let id: String
        var header: Header? = nil
        let books: [Book]
    }

    /// Hành động vuốt ngang của hàng (Bộ sưu tập: "Bỏ khỏi bộ"). Chỉ có ở kiểu danh sách — `LazyVGrid` không có
    /// `swipeActions`; kiểu lưới dựa vào sheet nhấn giữ (đã có cùng mục).
    struct SwipeAction {
        let title: String
        let systemImage: String
        let perform: (Book) -> Void
    }

    let groups: [BookGroup]
    let extensions: [Extension]
    let scope: BookListLayoutScope
    /// Còn truyện chưa hiện (phân trang 50/lượt của nơi dùng) ⇒ có sentinel tải thêm ở cuối.
    var hasMore: Bool = false
    var onLoadMore: () -> Void = {}
    var swipeAction: SwipeAction? = nil
    let onTap: (Book) -> Void
    let onLongPress: (Book) -> Void

    var body: some View {
        let layout = BookListLayoutPreferences.shared.layout(for: scope)
        if layout.mode.isGrid {
            gridView(layout)
        } else {
            listView(layout.rowSize)
        }
    }

    // MARK: - Danh sách

    private func listView(_ rowSize: BookListRowSize) -> some View {
        List {
            ForEach(groups) { group in
                if let header = group.header {
                    Section {
                        listRows(group.books, rowSize: rowSize)
                    } header: {
                        headerView(header)
                    }
                    .listSectionSeparator(.hidden)
                } else {
                    listRows(group.books, rowSize: rowSize)
                }
            }

            if hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .onAppear { scheduleLoadMore() }
                    Spacer()
                }
                .bookListPanelRowChrome()
            }
        }
        .listStyle(.plain)
    }

    private func listRows(_ books: [Book], rowSize: BookListRowSize) -> some View {
        ForEach(books) { book in
            listRow(book, rowSize: rowSize)
        }
    }

    @ViewBuilder
    private func listRow(_ book: Book, rowSize: BookListRowSize) -> some View {
        let row = ShelfBookRowView(book: book, extensions: extensions, rowSize: rowSize)
            .bookListPanelRow(rowSize)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap(book)
            }
            .onLongPressGesture(minimumDuration: BookSheetAction.longPressMinimumDuration) {
                onLongPress(book)
            }

        if let swipeAction {
            row.swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    swipeAction.perform(book)
                } label: {
                    Label(swipeAction.title, systemImage: swipeAction.systemImage)
                }
            }
        } else {
            row
        }
    }

    // MARK: - Lưới

    private func gridView(_ layout: BookListLayout) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
            count: layout.columns
        )
        let loadedCount = groups.reduce(0) { $0 + $1.books.count }

        // Tiêu đề nhóm (Đang ghim / Truyện khác / từng ngày) **dính đầu khi cuộn** như `List` `.plain` ở kiểu danh sách:
        // `pinnedViews: [.sectionHeaders]`. Lưới nằm **thẳng** trong `ScrollView` — bọc thêm một `LazyVStack` thì tiêu
        // đề không dính được.
        return ScrollView {
            LazyVGrid(
                columns: columns,
                alignment: .leading,
                spacing: layout.mode == .coverOnly ? 10 : 14,
                pinnedViews: [.sectionHeaders]
            ) {
                ForEach(groups) { group in
                    if let header = group.header {
                        Section {
                            gridCards(group.books, mode: layout.mode)
                        } header: {
                            pinnedHeader(header)
                        }
                    } else {
                        gridCards(group.books, mode: layout.mode)
                    }
                }

                // Sentinel là **footer** của một section rỗng: footer trải hết bề ngang lưới (một ô lưới chỉ chiếm một
                // cột) và được dựng lười — `onAppear` chỉ nổ khi cuộn tới cuối.
                if hasMore {
                    Section {
                        EmptyView()
                    } footer: {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .onAppear { scheduleLoadMore() }
                            // `id` theo số truyện đã hiện, đặt **ngoài** `onAppear`: tải thêm xong mà sentinel vẫn trong
                            // màn hình (lưới bìa ngang nhiều cột rất thấp) thì nó được dựng lại và `onAppear` chạy tiếp,
                            // không kẹt tới khi người dùng cuộn.
                            .id(loadedCount)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    /// Tiêu đề nhóm của kiểu lưới: nền đặc để thẻ cuộn qua bên dưới không lộ ra khi tiêu đề đang dính, nền tràn qua
    /// lề 16pt hai bên để phủ hết bề ngang như tiêu đề của `List`.
    private func pinnedHeader(_ header: Header) -> some View {
        headerView(header)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground).padding(.horizontal, -16))
    }

    private func gridCards(_ books: [Book], mode: BookListLayoutMode) -> some View {
        ForEach(books) { book in
            ShelfBookGridCardView(
                book: book,
                extensions: extensions,
                mode: mode,
                aspectRatio: scope.coverAspectRatio
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onTap(book)
            }
            .onLongPressGesture(minimumDuration: BookSheetAction.longPressMinimumDuration) {
                onLongPress(book)
            }
        }
    }

    // MARK: - Dùng chung

    private func headerView(_ header: Header) -> ShelfSectionHeaderView {
        ShelfSectionHeaderView(title: header.title, icon: header.icon, color: header.color, count: header.count)
    }

    /// Như bản cũ của Kệ/Lịch sử: nhích 0,3 s rồi mới tăng giới hạn, để lượt tải thêm không chen vào giữa lượt vẽ
    /// đang làm sentinel hiện ra.
    private func scheduleLoadMore() {
        let loadMore = onLoadMore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            loadMore()
        }
    }
}
