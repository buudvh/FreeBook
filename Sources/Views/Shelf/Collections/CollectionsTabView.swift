import SwiftUI
import SwiftData

/// Tab **Bộ sưu tập** của Kệ sách: grid thẻ ảnh ghép bìa, mở ra là danh sách truyện bên trong.
/// Không đọc/ghi `Book` trực tiếp — quan hệ N-N do `BookCollectionCoordinator` giữ.
///
/// Từ 1.3.339 là `ScrollView` + `LazyVGrid` thay cho `List`: bộ sưu tập nhận ra được bằng bìa truyện
/// chứ không phải một icon `folder` giống nhau ở mọi hàng.
///
/// Hai điều mất theo bản `List` và chỗ bù lại:
/// - `swipeActions` Đổi tên / Xoá ⇒ nay ở `.contextMenu` của thẻ (nhấn giữ) và ở menu trong
///   `CollectionDetailView`.
/// - `onMove` ⇒ nay ở `CollectionsReorderSheet`, vì `LazyVGrid` không có `onMove`.
///
/// **`LazyVGrid` phải nằm trong `ScrollView`, tuyệt đối không lồng trong một hàng `List`** — lazy
/// container trong cell của `List` làm layout tự vô hiệu giữa lượt cập nhật cell và trap
/// `EXC_BREAKPOINT` (đã crash thật ở 1.3.269, xem `10_risk_report`).
struct CollectionsTabView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\BookCollection.sortOrder), SortDescriptor(\BookCollection.createdAt)])
    private var collections: [BookCollection]

    @State private var showingReorderSheet = false
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
                gridView
            }
        }
        .sheet(isPresented: $showingReorderSheet) {
            CollectionsReorderSheet(collections: collections) { source, destination in
                reorderMessage(from: source, to: destination)
            }
        }
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

    // MARK: - Grid

    private let horizontalPadding: CGFloat = 16
    private let columnSpacing: CGFloat = 16

    @ViewBuilder
    private var gridView: some View {
        GeometryReader { geometry in
            // Cột `.fixed` theo bề rộng đã tính, không `.flexible`: thẻ và ảnh ghép bìa phải rộng đúng
            // bằng nhau, nếu để hệ thống tự chia thì `size` truyền cho mosaic lệch với cột.
            let cardSize = max(
                80,
                ((geometry.size.width - horizontalPadding * 2 - columnSpacing) / 2).rounded(.down)
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    gridHeader

                    LazyVGrid(
                        columns: [
                            GridItem(.fixed(cardSize), spacing: columnSpacing),
                            GridItem(.fixed(cardSize), spacing: columnSpacing)
                        ],
                        alignment: .leading,
                        spacing: 18
                    ) {
                        ForEach(collections) { collection in
                            CollectionGridCardView(
                                collection: collection,
                                size: cardSize,
                                onRename: { beginRename(collection) },
                                onDelete: { beginDelete(collection) }
                            )
                        }

                        createTile(size: cardSize)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 12)
            }
        }
    }

    private var gridHeader: some View {
        HStack {
            Text("\(collections.count) bộ sưu tập")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if collections.count > 1 {
                Button("Sắp xếp lại") { showingReorderSheet = true }
                    .font(.caption)
            }
        }
    }

    /// Ô cuối grid = tạo bộ mới. Cố ý **không** có nhãn chữ dưới ô để khớp bố cục thẻ.
    private func createTile(size: CGFloat) -> some View {
        Button {
            newName = ""
            showingCreateAlert = true
        } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: size * 0.24, weight: .light))
                        .foregroundColor(.secondary)
                )
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tạo bộ sưu tập mới")
    }

    private func beginRename(_ collection: BookCollection) {
        renameTargetId = collection.collectionId
        renameText = collection.name
        showingRenameAlert = true
    }

    private func beginDelete(_ collection: BookCollection) {
        deleteTargetId = collection.collectionId
        showingDeleteConfirm = true
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

    /// Trả `nil` khi thành công, hoặc câu lỗi — `CollectionsReorderSheet` tự phát toast, để tab này
    /// vẫn là chỗ duy nhất gọi coordinator.
    private func reorderMessage(from source: IndexSet, to destination: Int) -> String? {
        var ordered = collections.map { $0.collectionId }
        ordered.move(fromOffsets: source, toOffset: destination)
        let res = BookCollectionCoordinator.shared.reorderCollections(orderedIds: ordered, in: modelContext)
        if case .failure(let err) = res {
            return err.localizedDescription
        }
        return nil
    }
}
