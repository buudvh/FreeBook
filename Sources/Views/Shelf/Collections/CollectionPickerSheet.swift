import SwiftUI
import SwiftData

/// Chọn bộ sưu tập cho một truyện — hiện ra ngay sau khi thêm truyện vào kệ. **Được phép bỏ trống**:
/// truyện trên kệ không nhất thiết thuộc bộ nào.
///
/// Không cần nạp `Book`: một bộ có chứa truyện hay không đọc được từ `collection.books`.
struct CollectionPickerSheet: View {
    let bookId: String
    var title: String = "Thêm vào bộ sưu tập"

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BookCollection.sortOrder), SortDescriptor(\BookCollection.createdAt)])
    private var collections: [BookCollection]

    @State private var selected: Set<String> = []
    @State private var didPreload = false
    @State private var showingCreateAlert = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if collections.isEmpty {
                    Section {
                        Text("Chưa có bộ sưu tập nào. Tạo một bộ để nhóm các truyện theo ý bạn.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section {
                        ForEach(collections) { collection in
                            Button {
                                toggle(collection.collectionId)
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundColor(.accentColor)
                                    Text(collection.name)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if selected.contains(collection.collectionId) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    } footer: {
                        Text("Bỏ trống cũng được — truyện vẫn nằm trên kệ sách.")
                    }
                }

                Section {
                    Button {
                        newName = ""
                        showingCreateAlert = true
                    } label: {
                        Label("Tạo bộ sưu tập mới", systemImage: "folder.badge.plus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bỏ qua") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { commit() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: preloadSelection)
        .alert("Bộ sưu tập mới", isPresented: $showingCreateAlert) {
            TextField("Tên bộ sưu tập", text: $newName)
                .textInputAutocapitalization(.sentences)
            Button("Tạo") { createCollection() }
            Button("Hủy", role: .cancel) { newName = "" }
        }
    }

    private func preloadSelection() {
        guard !didPreload else { return }
        didPreload = true
        selected = Set(
            collections
                .filter { collection in collection.books.contains(where: { $0.bookId == bookId }) }
                .map { $0.collectionId }
        )
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func createCollection() {
        let res = BookCollectionCoordinator.shared.createCollection(name: newName, in: modelContext)
        newName = ""
        switch res {
        case .success(let collection):
            selected.insert(collection.collectionId)
        case .failure(let err):
            ToastManager.shared.show(message: err.localizedDescription, type: .error)
        }
    }

    private func commit() {
        let res = BookCollectionCoordinator.shared.setMemberships(bookId: bookId, collectionIds: selected, in: modelContext)
        switch res {
        case .success:
            dismiss()
        case .failure(let err):
            ToastManager.shared.show(message: err.localizedDescription, type: .error)
        }
    }
}
