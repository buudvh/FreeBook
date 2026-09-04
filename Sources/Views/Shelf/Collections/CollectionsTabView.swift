import SwiftUI
import SwiftData

/// Tab **Bộ sưu tập** của Kệ sách: danh sách các bộ do người dùng tạo, mở ra là danh sách truyện bên
/// trong. Không đọc/ghi `Book` trực tiếp — quan hệ N-N do `BookCollectionCoordinator` giữ.
struct CollectionsTabView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\BookCollection.sortOrder), SortDescriptor(\BookCollection.createdAt)])
    private var collections: [BookCollection]

    @State private var editMode: EditMode = .inactive
    @State private var showingCreateAlert = false
    @State private var newName = ""
    @State private var showingRenameAlert = false
    @State private var renameTargetId = ""
    @State private var renameText = ""
    @State private var showingDeleteConfirm = false
    @State private var deleteTargetId = ""

    private var deleteTargetName: String {
        collections.first(where: { $0.collectionId == deleteTargetId })?.name ?? ""
    }

    var body: some View {
        Group {
            if collections.isEmpty {
                emptyState
            } else {
                listView
            }
        }
        .environment(\.editMode, $editMode)
        .alert("Bộ sưu tập mới", isPresented: $showingCreateAlert) {
            TextField("Tên bộ sưu tập", text: $newName)
                .textInputAutocapitalization(.sentences)
            Button("Tạo") { createCollection() }
            Button("Hủy", role: .cancel) { newName = "" }
        }
        .alert("Đổi tên bộ sưu tập", isPresented: $showingRenameAlert) {
            TextField("Tên bộ sưu tập", text: $renameText)
                .textInputAutocapitalization(.sentences)
            Button("Lưu") { commitRename() }
            Button("Hủy", role: .cancel) { renameTargetId = "" }
        }
        .confirmationDialog(
            "Xoá bộ sưu tập \"\(deleteTargetName)\"?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Xoá bộ sưu tập", role: .destructive) { commitDelete() }
            Button("Hủy", role: .cancel) { deleteTargetId = "" }
        } message: {
            Text("Chỉ bộ sưu tập bị xoá. Các truyện bên trong vẫn ở nguyên trên kệ sách.")
        }
    }

    // MARK: - Danh sách

    @ViewBuilder
    private var listView: some View {
        List {
            Section {
                ForEach(collections) { collection in
                    NavigationLink(destination: CollectionDetailView(collectionId: collection.collectionId)) {
                        collectionRow(collection)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteTargetId = collection.collectionId
                            showingDeleteConfirm = true
                        } label: {
                            Label("Xoá", systemImage: "trash")
                        }

                        Button {
                            renameTargetId = collection.collectionId
                            renameText = collection.name
                            showingRenameAlert = true
                        } label: {
                            Label("Đổi tên", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                    // Swipe action một mình là quá kín: từ 1.3.336 nhấn giữ cũng ra đúng hai việc đó.
                    .contextMenu {
                        Button {
                            renameTargetId = collection.collectionId
                            renameText = collection.name
                            showingRenameAlert = true
                        } label: {
                            Label("Đổi tên", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            deleteTargetId = collection.collectionId
                            showingDeleteConfirm = true
                        } label: {
                            Label("Xoá bộ sưu tập", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveCollections)
            } header: {
                HStack {
                    Text("\(collections.count) bộ sưu tập")
                    Spacer()
                    Button(editMode == .active ? "Xong" : "Sắp xếp lại") {
                        editMode = editMode == .active ? .inactive : .active
                    }
                    .font(.caption)
                    .textCase(nil)
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
    }

    @ViewBuilder
    private func collectionRow(_ collection: BookCollection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("\(collection.books.count) truyện")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.secondary)

            Text("Chưa có bộ sưu tập nào")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Tạo bộ sưu tập để nhóm các truyện trên kệ theo ý bạn. Một truyện có thể nằm trong nhiều bộ.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                newName = ""
                showingCreateAlert = true
            } label: {
                Label("Tạo bộ sưu tập", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Thao tác

    private func createCollection() {
        let res = BookCollectionCoordinator.shared.createCollection(name: newName, in: modelContext)
        newName = ""
        switch res {
        case .success(let collection):
            ToastManager.shared.show(message: "Đã tạo bộ sưu tập '\(collection.name)'", type: .success)
        case .failure(let err):
            ToastManager.shared.show(message: err.localizedDescription, type: .error)
        }
    }

    private func commitRename() {
        let id = renameTargetId
        renameTargetId = ""
        guard !id.isEmpty else { return }
        let res = BookCollectionCoordinator.shared.renameCollection(collectionId: id, name: renameText, in: modelContext)
        if case .failure(let err) = res {
            ToastManager.shared.show(message: err.localizedDescription, type: .error)
        }
    }

    private func commitDelete() {
        let id = deleteTargetId
        deleteTargetId = ""
        guard !id.isEmpty else { return }
        let res = BookCollectionCoordinator.shared.deleteCollection(collectionId: id, in: modelContext)
        switch res {
        case .success:
            ToastManager.shared.show(message: "Đã xoá bộ sưu tập", type: .success)
        case .failure(let err):
            ToastManager.shared.show(message: err.localizedDescription, type: .error)
        }
    }

    private func moveCollections(from source: IndexSet, to destination: Int) {
        var ordered = collections.map { $0.collectionId }
        ordered.move(fromOffsets: source, toOffset: destination)
        let res = BookCollectionCoordinator.shared.reorderCollections(orderedIds: ordered, in: modelContext)
        if case .failure(let err) = res {
            ToastManager.shared.show(message: err.localizedDescription, type: .error)
        }
    }
}
