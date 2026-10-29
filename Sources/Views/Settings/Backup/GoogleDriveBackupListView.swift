import SwiftData
import SwiftUI

/// Tab Google Drive của màn Sao lưu: đăng nhập, xem danh sách `.fbbackup` trên Drive, khôi phục
/// một chạm, tải về máy, xoá. Việc tải lên nằm ở menu từng bản trong danh sách local.
///
/// Chưa cấu hình client id thì màn này chỉ hiện ô dán — **kênh local vẫn chạy bình thường**.
struct GoogleDriveBackupListView: View {
    @ObservedObject var coordinator: BackupCoordinator
    @Environment(\.modelContext) private var modelContext

    @State private var clientIdInput = ""
    @State private var isConfigured = GoogleDriveConfiguration.isConfigured
    @State private var deletingFile: GoogleDriveFile?
    /// Bản đang mở ngăn kéo "…"; `nil` = đóng.
    @State private var menuFile: GoogleDriveFile?

    var body: some View {
        List {
            if coordinator.progress.isActive {
                progressSection
            }
            if isConfigured {
                accountSection
                if coordinator.isDriveSignedIn {
                    filesSection
                }
            } else {
                configurationSection
            }
        }
        .backPageTitle("Google Drive")
        // Gắn ở `List` (luôn được dựng), không ở header/footer của section — chúng có thể chưa dựng khi cuộn khuất.
        .sideDrawerMenu(item: $menuFile, title: { $0.name }) { file in fileMenuItems(file) }
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
        .task {
            guard isConfigured, coordinator.isDriveSignedIn, coordinator.driveFiles.isEmpty else { return }
            await coordinator.refreshDriveFiles()
        }
    }

    // MARK: - Tiến trình

    /// Cùng cách giữ chiều cao cố định như `BackupHubView`: 2 dòng dành sẵn + một `ProgressView`
    /// kiểu `.linear`, để thông báo dài ngắn khác nhau không làm giật danh sách.
    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(coordinator.progress.message)
                    .font(.subheadline)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ProgressView(value: coordinator.progress.fraction)
                    .progressViewStyle(.linear)
            }
            .padding(.vertical, 2)
            .animation(nil, value: coordinator.progress.message)
        }
    }

    // MARK: - Chưa cấu hình

    private var configurationSection: some View {
        Section {
            TextField("xxxxx.apps.googleusercontent.com", text: $clientIdInput)
                .textInputAutocapitalization(.never)
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
            SectionHelpHeader("Chưa cấu hình Google Drive", paragraphs: ["Bản cài này không có Google Client ID (loại iOS). Dán client id vào đây để dùng Drive, hoặc bỏ qua — sao lưu vào máy và xuất ra Files vẫn hoạt động đầy đủ."])
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
                .disabled(coordinator.isBusy)
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
            SectionHelpHeader("Tài khoản", paragraphs: ["App chỉ xin quyền với những file do chính nó tạo, trong thư mục \(GoogleDriveConfiguration.folderName)."])
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
            filesHeader
        }
    }

    private var filesHeader: some View {
        SectionHelpHeader("Trên Google Drive", paragraphs: ["“Khôi phục ngay tất cả” tự tải bản sao lưu về rồi gộp mọi nhóm dữ liệu vào máy, không hỏi lại. Muốn chọn từng nhóm thì dùng “Tải về máy” rồi khôi phục từ danh sách ở máy."])
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
            // `.borderless`: trong hàng của `List`, nút mặc định biến cả hàng thành vùng bấm.
            Button {
                menuFile = file
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.white)
            }
            .buttonStyle(.borderless)
        }
    }

    /// Nội dung ngăn kéo "…" của một bản trên Drive (ngăn kéo gắn ở `List` của `body`, không gắn từng hàng).
    @ViewBuilder
    private func fileMenuItems(_ file: GoogleDriveFile) -> some View {
        SideDrawerActionRow("Khôi phục ngay tất cả", systemImage: "arrow.clockwise.icloud") { startRestoreEverything(file) }
            .disabled(coordinator.isBusy)
        SideDrawerActionRow("Tải về máy", systemImage: "icloud.and.arrow.down") {
            Task { await coordinator.downloadFromDrive(file) }
        }
        .disabled(coordinator.isBusy)
        SideDrawerActionRow("Xoá trên Drive", systemImage: "trash", role: .destructive) { deletingFile = file }
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deletingFile != nil }, set: { if !$0 { deletingFile = nil } })
    }

    /// Một chạm: tải về → khôi phục **toàn bộ** nhóm dữ liệu, không hiện hộp thoại chọn nhóm.
    ///
    /// **Không** còn chặn khi TTS đang phát (người dùng chốt 2026-10-07). Đánh đổi đã biết: khôi phục ghi
    /// vào đúng hàng SwiftData mà TTS đang giữ tiến độ.
    private func startRestoreEverything(_ file: GoogleDriveFile) {
        let container = modelContext.container
        Task { await coordinator.restoreEverythingFromDrive(file, container: container) }
    }

    private static func dateText(_ date: Date) -> String {
        guard date > Date.distantPast else { return "Không rõ ngày" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
