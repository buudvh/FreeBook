import SwiftUI
import SwiftData

/// Sheet hiện ra khi **nhấn giữ** một cuốn sách ở Kệ sách / Lịch sử / trong một bộ sưu tập.
///
/// Thay cho `.contextMenu` cũ: menu ngữ cảnh của SwiftUI chỉ nhận được `Button`/`Link`, không dựng
/// được phần đầu có ảnh bìa lẫn danh sách bộ sưu tập bấm thêm/bớt tại chỗ.
///
/// Từ 1.3.334 hai mục "Xem chi tiết" và "Ghim" **không còn là hàng riêng**: phần đầu (bìa + tên) chạm
/// để xem chi tiết, nhấn giữ để ghim/bỏ ghim. Điều kiện hiện hai hành động đó giữ y như khi chúng còn
/// là hàng — chi tiết chỉ có với truyện không phải TXT nội bộ (hoặc ở Lịch sử), ghim không có ở Lịch sử.
///
/// Từ 1.3.337 hai hàng kệ sách cũng rời danh sách: `shelfToggleButton` ở **góc dưới phải** phần đầu làm
/// cả hai chiều, chọn theo `book.isOnShelf`. Sheet **không** còn `NavigationStack`, tiêu đề "Tuỳ chọn
/// truyện" và nút "Xong" — chỉ còn tay cầm vuốt xuống.
///
/// Sheet **tự** lo phần bộ sưu tập (qua `BookCollectionCoordinator`), còn các hành động khác chỉ phát
/// `BookSheetAction` cho màn gọi nó xử lý — vì chúng cần navigation/sheet của riêng màn đó.
struct BookActionSheet: View {
    let target: BookSheetAction.Target
    var isCheckingNewChapters: Bool = false
    let onAction: (BookSheetAction) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BookCollection.sortOrder), SortDescriptor(\BookCollection.createdAt)])
    private var allCollections: [BookCollection]

    @State private var showingCreateAlert = false
    @State private var newCollectionName = ""
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    private var book: Book { target.book }

    /// `nil` khi sheet không mở từ trong một bộ sưu tập. Bóc ra thành computed property để phần thân
    /// `@ViewBuilder` chỉ dùng `if let` — khớp đúng lối viết của các view khác trong repo.
    private var currentCollectionId: String? {
        if case .collection(let id) = target.mode { return id }
        return nil
    }

    private var memberCollections: [BookCollection] {
        book.collections.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
        }
    }

    private var availableCollections: [BookCollection] {
        let memberIds = Set(book.collections.map { $0.collectionId })
        return allCollections.filter { !memberIds.contains($0.collectionId) }
    }

    var body: some View {
        List {
            Section {
                header
            } footer: {
                Text(headerHint)
            }

            Section {
                collectionRows
            } header: {
                Text("Bộ sưu tập")
            } footer: {
                Text("Bỏ khỏi bộ sưu tập không xoá truyện khỏi kệ sách.")
            }

            Section {
                actionRows
            }
        }
        .listStyle(.insetGrouped)
        .presentationDetents([.medium, .large])
        // Không còn nút "Xong" nên phải để lộ tay cầm: vuốt xuống là đường đóng duy nhất.
        .presentationDragIndicator(.visible)
        .alert("Bộ sưu tập mới", isPresented: $showingCreateAlert) {
            TextField("Tên bộ sưu tập", text: $newCollectionName)
                .textInputAutocapitalization(.sentences)
            Button("Tạo") { createCollectionAndAdd() }
            Button("Hủy", role: .cancel) { newCollectionName = "" }
        } message: {
            Text("Truyện sẽ được thêm vào bộ sưu tập vừa tạo.")
        }
    }

    // MARK: - Phần đầu

    /// Chi tiết chỉ mở được khi truyện có nguồn để mở: đúng điều kiện của hàng "Xem chi tiết" cũ.
    private var canOpenDetail: Bool {
        target.mode == .history || !book.isLocalBook
    }

    private var canTogglePin: Bool {
        target.mode != .history
    }

    private var headerHint: String {
        let shelf = "Nút góc dưới phải: \(book.isOnShelf ? "xoá khỏi kệ sách" : "thêm vào kệ sách")."
        switch (canOpenDetail, canTogglePin) {
        case (true, true):
            return "Chạm phần trên để xem chi tiết, nhấn giữ để \(book.isPinned ? "bỏ ghim" : "ghim lên đầu kệ"). \(shelf)"
        case (true, false):
            return "Chạm phần trên để xem chi tiết. \(shelf)"
        case (false, true):
            return "Nhấn giữ phần trên để \(book.isPinned ? "bỏ ghim" : "ghim lên đầu kệ"). \(shelf)"
        case (false, false):
            return shelf
        }
    }

    /// Phần đầu chia làm **hai vùng cạnh nhau, không lồng nhau**: khối bìa + tên nhận cử chỉ chạm/nhấn
    /// giữ, cột phải chứa hai icon. Đặt nút kệ sách trong `overlay` lên trên vùng có cử chỉ là để hai
    /// bên tranh nhau cùng một cú chạm, nên nó là *sibling*.
    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            headerTappableContent
            headerTrailingColumn
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var headerTappableContent: some View {
        HStack(alignment: .top, spacing: 12) {
            BookCoverView(bookId: book.bookId, coverUrl: book.coverUrl, width: 60, height: 84)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 6) {
                Text(DisplayTextFormatter.titleCase(displayedTitle))
                    .font(.headline)
                    .lineLimit(3)

                if !book.author.isEmpty {
                    Text(DisplayTextFormatter.titleCase(displayedAuthor))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if book.isPinned {
                    Label("Đang ghim đầu kệ", systemImage: "pin.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        // `onTapGesture` phải đăng ký **trước** `onLongPressGesture`, ngược lại chạm nhanh cũng bị
        // nhận diện là nhấn giữ và không bao giờ mở được chi tiết.
        .onTapGesture {
            guard canOpenDetail else { return }
            emit(.openDetail)
        }
        .onLongPressGesture(minimumDuration: BookSheetAction.longPressMinimumDuration) {
            guard canTogglePin else { return }
            BookSheetAction.playLongPressFeedback()
            emit(.togglePin)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DisplayTextFormatter.titleCase(displayedTitle))
        .accessibilityHint(headerHint)
        .accessibilityAddTraits(canOpenDetail ? .isButton : [])
    }

    /// `minHeight: 84` khớp chiều cao ảnh bìa nên nút luôn nằm đúng đáy panel ngay cả khi tên truyện
    /// ngắn; `maxHeight: .infinity` để cột giãn theo hàng khi tên dài hơn ảnh bìa. Thiếu một trong hai
    /// thì nút trôi lên giữa panel.
    @ViewBuilder
    private var headerTrailingColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if canOpenDetail {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 8)

            shelfToggleButton
        }
        .frame(minHeight: 84, maxHeight: .infinity, alignment: .trailing)
    }

    /// Hai hàng "Thêm vào kệ sách" / "Xoá khỏi kệ sách" cũ gộp thành **một** nút icon ở góc dưới phải
    /// của phần đầu: trạng thái suy ra từ `book.isOnShelf` nên không bao giờ hiện cả hai.
    @ViewBuilder
    private var shelfToggleButton: some View {
        Button {
            emit(book.isOnShelf ? .removeFromShelfOnly : .addToShelf)
        } label: {
            Image(systemName: book.isOnShelf ? "bookmark.slash.fill" : "bookmark.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(book.isOnShelf ? .red : .accentColor)
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(book.isOnShelf ? "Xoá khỏi kệ sách" : "Thêm vào kệ sách")
    }

    private var displayedTitle: String {
        TranslateUtils.translateBookTitleIfNeeded(book.title, bookId: book.bookId)
    }

    private var displayedAuthor: String {
        isTranslationEnabled ? TranslateUtils.translateAuthorHanViet(book.author) : book.author
    }

    // MARK: - Bộ sưu tập

    @ViewBuilder
    private var collectionRows: some View {
        if memberCollections.isEmpty {
            Text("Chưa thuộc bộ sưu tập nào")
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else {
            ForEach(memberCollections) { collection in
                HStack {
                    Image(systemName: "folder")
                        .foregroundColor(.accentColor)
                    Text(collection.name)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        BookActionRunner.removeFromCollection(book, collectionId: collection.collectionId, in: modelContext)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bỏ khỏi \(collection.name)")
                }
            }
        }

        // Dấu "+" **cuối danh sách** theo yêu cầu: chọn bộ có sẵn hoặc tạo bộ mới ngay tại đây.
        Menu {
            ForEach(availableCollections) { collection in
                Button {
                    addToCollection(collection.collectionId)
                } label: {
                    Label(collection.name, systemImage: "folder")
                }
            }

            if !availableCollections.isEmpty {
                Divider()
            }

            Button {
                newCollectionName = ""
                showingCreateAlert = true
            } label: {
                Label("Tạo bộ sưu tập mới…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("Thêm vào bộ sưu tập", systemImage: "plus.circle.fill")
        }
    }

    private func addToCollection(_ collectionId: String) {
        let res = BookCollectionCoordinator.shared.addBook(bookId: book.bookId, toCollection: collectionId, in: modelContext)
        if case .failure(let err) = res {
            AppLogger.shared.log("❌ [BookActionSheet] Lỗi thêm vào bộ sưu tập: \(err.localizedDescription)")
            ToastManager.shared.show(message: err.localizedDescription, type: .error)
        }
    }

    private func createCollectionAndAdd() {
        let res = BookCollectionCoordinator.shared.createCollection(name: newCollectionName, in: modelContext)
        newCollectionName = ""
        switch res {
        case .success(let collection):
            addToCollection(collection.collectionId)
        case .failure(let err):
            ToastManager.shared.show(message: err.localizedDescription, type: .error)
        }
    }

    // MARK: - Hành động

    /// Hai hàng kệ sách ("Thêm vào kệ sách" / "Xoá khỏi kệ sách") **không** còn ở đây — chúng thành một
    /// nút icon ở góc dưới phải phần đầu (xem `shelfToggleButton`).
    @ViewBuilder
    private var actionRows: some View {
        if target.mode != .history, !book.isLocalBook {
            actionRow(.checkNewChapters, "Kiểm tra chương mới", "bell.badge")
                .disabled(isCheckingNewChapters)
        }

        if !book.isLocalBook {
            actionRow(.changeSource, "Đổi nguồn", "arrow.triangle.2.circlepath")
        }

        actionRow(.editInfo, "Sửa thông tin", "square.and.pencil")
        actionRow(.download, "Tải truyện", "arrow.down.circle")
        actionRow(.exportEbook, "Xuất ebook", "square.and.arrow.up")
        actionRow(.retranslateChapterTitles, "Dịch lại tên chương", "arrow.clockwise.circle")

        if currentCollectionId != nil {
            actionRow(.removeFromCurrentCollection, "Bỏ khỏi bộ sưu tập này", "folder.badge.minus")
                .accessibilityHint("Truyện vẫn ở trên kệ sách")
        }

        if target.mode == .history {
            destructiveRow(.removeFromHistory, "Xóa lịch sử", "clock.badge.xmark")
        } else {
            destructiveRow(.deleteBook, "Xoá", "trash.fill")
        }
    }

    private func actionRow(_ action: BookSheetAction, _ title: String, _ icon: String) -> some View {
        Button {
            emit(action)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func destructiveRow(_ action: BookSheetAction, _ title: String, _ icon: String) -> some View {
        Button(role: .destructive) {
            emit(action)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    /// Đóng sheet **trước**, phát hành động ở turn sau. Nhiều hành động mở tiếp một sheet khác
    /// (`TaskOptionsSheet`, `BookInfoEditView`) hoặc một navigation; phát ngay trong lúc sheet này còn
    /// đang đóng làm hai lớp trình bày chọi nhau và lớp mới không hiện — cùng lý do với
    /// `NotificationInboxView(onOpenBook:)` ở `ShelfView`.
    private func emit(_ action: BookSheetAction) {
        dismiss()
        let handler = onAction
        DispatchQueue.main.async {
            handler(action)
        }
    }
}
