import SwiftUI

/// Tab Google Drive của màn Sao lưu: đăng nhập, xem danh sách `.fbbackup` trên Drive, tải về máy,
/// xoá. Việc tải lên nằm ở menu từng bản trong danh sách local.
///
/// Chưa cấu hình client id thì màn này chỉ hiện ô dán — **kênh local vẫn chạy bình thường**.
struct GoogleDriveBackupListView: View {
    @ObservedObject var coordinator: BackupCoordinator

    @State private var clientIdInput = ""
    @State private var isConfigured = GoogleDriveConfiguration.isConfigured
    @State private var deletingFile: GoogleDriveFile?

    var body: some View {
        List {
            if isConfigured {
                accountSection
                if coordinator.isDriveSignedIn {
                    filesSection
                }
            } else {
                configurationSection
            }
        }
        .navigationTitle("Google Drive")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard isConfigured, coordinator.isDriveSignedIn, coordinator.driveFiles.isEmpty else { return }
            await coordinator.refreshDriveFiles()
        }
    }

    // MARK: - Chưa cấu hình

    private var configurationSection: some View {
        Section {
            TextField("xxxxx.apps.googleusercontent.com", text: $clientIdInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote)
            Button("Lưu Client ID") {
                GoogleDriveConfiguration.saveClientIdOverride(clientIdInput)
                isConfigured = GoogleDriveConfiguration.isConfigured
                if !isConfigured {
                    ToastManager.shared.show(message: "Client ID không hợp lệ", type: .error)
                }
            }
            .disabled(clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Chưa cấu hình Google Drive")
        } footer: {
            Text("Bản cài này không có Google Client ID (loại iOS). Dán client id vào đây để dùng Drive, hoặc bỏ qua — sao lưu vào máy và xuất ra Files vẫn hoạt động đầy đủ.")
        }
    }

    // MARK: - Tài khoản

    private var accountSection: some View {
        Section {
            if coordinator.isDriveSignedIn {
                Button {
                    coordinator.signOutDrive()
                } label: {
                    Label("Đăng xuất Google Drive", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.red)
                }
                Button {
                    Task { await coordinator.refreshDriveFiles() }
                } label: {
                    Label("Làm mới danh sách", systemImage: "arrow.clockwise")
                }
                .disabled(coordinator.isBusy)
            } else {
                Button {
                    Task { await coordinator.signInDrive() }
                } label: {
                    Label("Đăng nhập Google Drive", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(coordinator.isBusy)
            }
        } header: {
            Text("Tài khoản")
        } footer: {
            Text("App chỉ xin quyền với những file do chính nó tạo, trong thư mục \(GoogleDriveConfiguration.folderName).")
        }
    }

    // MARK: - Danh sách file

    private var filesSection: some View {
        Section {
            if coordinator.driveFiles.isEmpty {
                Text("Thư mục \(GoogleDriveConfiguration.folderName) chưa có bản sao lưu nào")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(coordinator.driveFiles) { file in
                    row(for: file)
                }
            }
        } header: {
            Text("Trên Google Drive")
        } footer: {
            footer
        }
    }

    private var footer: some View {
        Text("Tải về xong, bản sao lưu xuất hiện trong danh sách ở máy — khôi phục từ đó.")
            .confirmationDialog(
                "Xoá \(deletingFile?.name ?? "") trên Drive?",
                isPresented: isDeleting,
                titleVisibility: .visible
            ) {
                Button("Xoá trên Drive", role: .destructive) {
                    if let file = deletingFile {
                        Task { await coordinator.deleteFromDrive(file) }
                    }
                    deletingFile = nil
                }
                Button("Huỷ", role: .cancel) { deletingFile = nil }
            }
    }

    private func row(for file: GoogleDriveFile) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(Self.dateText(file.createdAt)) · \(file.displaySize)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button {
                    Task { await coordinator.downloadFromDrive(file) }
                } label: {
                    Label("Tải về máy", systemImage: "icloud.and.arrow.down")
                }
                .disabled(coordinator.isBusy)

                Button(role: .destructive) {
                    deletingFile = file
                } label: {
                    Label("Xoá trên Drive", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.accentColor)
            }
        }
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deletingFile != nil }, set: { if !$0 { deletingFile = nil } })
    }

    private static func dateText(_ date: Date) -> String {
        guard date > Date.distantPast else { return "Không rõ ngày" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
