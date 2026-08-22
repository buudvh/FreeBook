import SwiftUI

/// Section liệt kê các file `.fbbackup` trong `backups/` kèm menu hành động cho từng bản.
///
/// Alert đổi tên và hộp thoại xoá gắn vào footer (một view lá) thay vì vào `Section` —
/// modifier đặt trên `Section` sẽ lan xuống từng hàng và bật nhiều lần cùng một binding.
struct LocalBackupListView: View {
    @ObservedObject var coordinator: BackupCoordinator
    let isTTSPlaying: Bool
    let canUploadToDrive: Bool
    let onRestore: (LocalBackupStore.Item) -> Void
    let onShare: (LocalBackupStore.Item) -> Void
    let onUpload: (LocalBackupStore.Item) -> Void

    @State private var renamingItem: LocalBackupStore.Item?
    @State private var renameText = ""
    @State private var deletingItem: LocalBackupStore.Item?

    var body: some View {
        Section {
            if coordinator.localBackups.isEmpty {
                Text("Chưa có bản sao lưu nào trong máy")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(coordinator.localBackups) { item in
                    row(for: item)
                }
            }
        } header: {
            Text("Bản sao lưu trong máy")
        } footer: {
            footer
        }
    }

    private var footer: some View {
        Text(coordinator.localBackups.isEmpty
             ? "File sao lưu nằm trong vùng dữ liệu của app, xoá app là mất — nên xuất ra Files hoặc Google Drive."
             : "Tổng \(BackupSizeEstimator.format(coordinator.localBackups.reduce(Int64(0)) { $0 + $1.byteCount })).")
            .alert("Đổi tên bản sao lưu", isPresented: isRenaming) {
                TextField("Tên mới", text: $renameText)
                Button("Huỷ", role: .cancel) { renamingItem = nil }
                Button("Lưu") {
                    if let item = renamingItem {
                        coordinator.renameLocal(item, to: renameText)
                    }
                    renamingItem = nil
                }
            }
            .confirmationDialog(
                "Xoá \(deletingItem?.name ?? "")?",
                isPresented: isDeleting,
                titleVisibility: .visible
            ) {
                Button("Xoá bản sao lưu", role: .destructive) {
                    if let item = deletingItem {
                        coordinator.deleteLocal(item)
                    }
                    deletingItem = nil
                }
                Button("Huỷ", role: .cancel) { deletingItem = nil }
            }
    }

    private func row(for item: LocalBackupStore.Item) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.baseName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(Self.dateText(item.createdAt)) · \(item.displaySize)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button {
                    onRestore(item)
                } label: {
                    Label("Khôi phục từ bản này", systemImage: "arrow.counterclockwise")
                }
                .disabled(isTTSPlaying || coordinator.isBusy)

                Button {
                    onShare(item)
                } label: {
                    Label("Xuất ra Files", systemImage: "square.and.arrow.up")
                }

                if canUploadToDrive {
                    Button {
                        onUpload(item)
                    } label: {
                        Label("Tải lên Google Drive", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(coordinator.isBusy)
                }

                Button {
                    renameText = item.baseName
                    renamingItem = item
                } label: {
                    Label("Đổi tên", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    deletingItem = item
                } label: {
                    Label("Xoá", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.accentColor)
            }
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renamingItem != nil }, set: { if !$0 { renamingItem = nil } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } })
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
