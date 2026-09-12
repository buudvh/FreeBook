import SwiftUI

/// Section liệt kê các file `.fbbackup` trong `backups/` kèm menu hành động cho từng bản.
///
/// Alert đổi tên và hộp thoại xoá gắn vào footer (một view lá) thay vì vào `Section` —
/// modifier đặt trên `Section` sẽ lan xuống từng hàng và bật nhiều lần cùng một binding.
struct LocalBackupListView: View {
    @ObservedObject var coordinator: BackupCoordinator
    let isTTSPlaying: Bool
    let canUploadToDrive: Bool
    let canUploadToTelegram: Bool
    let onRestore: (LocalBackupStore.Item) -> Void
    let onShare: (LocalBackupStore.Item) -> Void
    let onUpload: (LocalBackupStore.Item) -> Void
    let onTelegram: (LocalBackupStore.Item) -> Void

    @State private var renamingItem: LocalBackupStore.Item?
    @State private var renameText = ""
    /// Gộp "xoá một bản" và "xoá tất cả" vào **một** trạng thái: hộp thoại xác nhận chỉ được có một
    /// binding bật tại một thời điểm, hai cờ song song sẽ tranh nhau trình bày.
    @State private var deleteTarget: DeleteTarget?

    private enum DeleteTarget: Equatable {
        case one(LocalBackupStore.Item)
        case all
    }

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

                Button(role: .destructive) {
                    deleteTarget = .all
                } label: {
                    Label("Xoá tất cả bản sao lưu trong máy", systemImage: "trash")
                }
                .disabled(coordinator.isBusy)
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
                deleteDialogTitle,
                isPresented: isDeleting,
                titleVisibility: .visible
            ) {
                Button(deleteDialogConfirmLabel, role: .destructive) {
                    switch deleteTarget {
                    case .one(let item):
                        coordinator.deleteLocal(item)
                    case .all:
                        coordinator.deleteAllLocal()
                    case nil:
                        break
                    }
                    deleteTarget = nil
                }
                Button("Huỷ", role: .cancel) { deleteTarget = nil }
            } message: {
                if deleteTarget == .all {
                    Text("Toàn bộ \(coordinator.localBackups.count) bản trong máy sẽ bị xoá. Bản đã tải lên Google Drive hoặc Telegram không bị ảnh hưởng.")
                }
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

                if canUploadToTelegram {
                    Button {
                        onTelegram(item)
                    } label: {
                        Label("Gửi qua Telegram", systemImage: "paperplane")
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
                    deleteTarget = .one(item)
                } label: {
                    Label("Xoá", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.white)
            }
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renamingItem != nil }, set: { if !$0 { renamingItem = nil } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var deleteDialogTitle: String {
        switch deleteTarget {
        case .one(let item): return "Xoá \(item.name)?"
        case .all: return "Xoá tất cả \(coordinator.localBackups.count) bản sao lưu trong máy?"
        case nil: return ""
        }
    }

    private var deleteDialogConfirmLabel: String {
        if case .all = deleteTarget { return "Xoá tất cả" }
        return "Xoá bản sao lưu"
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
