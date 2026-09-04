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
        NavigationStack {
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
            .navigationTitle("Tuỳ chọn truyện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
        switch (canOpenDetail, canTogglePin) {
        case (true, true):
            return "Chạm phần trên để xem chi tiết, nhấn giữ để \(book.isPinned ? "bỏ ghim" : "ghim lên đầu kệ")."
        case (true, false):
            return "Chạm phần trên để xem chi tiết."
        case (false, true):
            return "Nhấn giữ phần trên để \(book.isPinned ? "bỏ ghim" : "ghim lên đầu kệ")."
        case (false, false):
            return "Bỏ khỏi bộ sưu tập không xoá truyện khỏi kệ sách."
        }
    }

    @ViewBuilder
    private var header: some View {
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

            if canOpenDetail {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // `onTapGesture` phải đăng ký **trước** `onLongPressGesture`, ngược lại chạm nhanh cũng bị
        // nhận diện là nhấn giữ và không bao giờ mở được chi tiết.
        .onTapGesture {
            guard canOpenDetail else { return }
            emit(.openDetail)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            guard canTogglePin else { return }
            emit(.togglePin)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DisplayTextFormatter.titleCase(displayedTitle))
        .accessibilityHint(headerHint)
        .accessibilityAddTraits(canOpenDetail ? .isButton : [])
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

    @ViewBuilder
    private var actionRows: some View {
        if target.mode == .history {
            if !book.isOnShelf {
                actionRow(.addToShelf, "Thêm vào kệ sách", "plus.circle.fill")
            }
        } else if !book.isLocalBook {
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
            actionRow(.removeFromShelfOnly, "Xoá khỏi kệ sách", "bookmark.slash")
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
