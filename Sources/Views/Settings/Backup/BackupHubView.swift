import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Màn Sao lưu & Khôi phục: chọn nhóm nội dung, tạo file `.fbbackup`, quản lý bản trong máy,
/// nhập file từ Files và mở tab Google Drive.
///
/// Mọi ghi dữ liệu đi qua `BackupCoordinator` (View không chạm `modelContext.insert/save`).
///
/// **Không** còn chặn khôi phục khi TTS đang phát (người dùng chốt 2026-10-07). Trước đây màn này đọc
/// trạng thái TTS qua projection reader chỉ để chặn; nay bỏ hẳn, kèm đánh đổi đã biết: khôi phục ghi vào
/// đúng hàng SwiftData mà TTS đang giữ tiến độ, nên TTS có thể đọc nhầm hoặc lỗi giữa chừng.
struct BackupHubView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var coordinator = BackupCoordinator.shared

    @State private var scopes = BackupScope.defaultSelection
    @State private var showingImporter = false
    @State private var sharingItem: LocalBackupStore.Item?
    @State private var showingRestoreOptions = false
    @State private var restoreSourceName = ""
    /// Bật khi người dùng bấm "Khôi phục": `onDismiss` của sheet chạy **trước** khi task khôi phục
    /// kịp đặt `isBusy`, nếu không có cờ này thì thư mục tạm bị dọn ngay dưới chân worker.
    @State private var isConfirmingRestore = false

    private static var archiveType: UTType {
        UTType(filenameExtension: BackupPaths.fileExtension) ?? .data
    }

    private static var manifestType: UTType {
        UTType(filenameExtension: BackupMultipartArchive.manifestExtension) ?? .data
    }

    var body: some View {
        List {
            if coordinator.progress.isActive {
                progressSection
            }

            BackupScopeToggleList(selection: $scopes)
            createSection

            LocalBackupListView(
                coordinator: coordinator,
                canUploadToDrive: GoogleDriveConfiguration.isConfigured && coordinator.isDriveSignedIn,
                canUploadToTelegram: TelegramConfiguration.isConfigured,
                onRestore: startRestore,
                onShare: { sharingItem = $0 },
                onUpload: { item in Task { await coordinator.uploadToDrive(item) } },
                onTelegram: { item in Task { await coordinator.uploadToTelegram(item) } }
            )

            driveSection
        }
        .navigationTitle("Sao Lưu & Khôi Phục")
        .onAppear { coordinator.refreshLocal() }
        .sheet(isPresented: $showingImporter) { importer }
        .sheet(item: $sharingItem) { ShareSheet(activityItems: [$0.url]) }
        .sheet(isPresented: $showingRestoreOptions, onDismiss: discardPreparedRestore) { restoreSheet }
        // Toast kết quả sao lưu / khôi phục **không** còn ở đây: `MainTabView` (root) đã observe
        // `lastMessage`/`lastError`, nên toast hiện kể cả khi người dùng đã rời màn này giữa chừng. Giữ
        // thêm observer ở đây là mỗi lượt hiện hai toast.
    }

    // MARK: - Các section

    /// Chiều cao **không đổi** trong suốt tiến trình: thông báo dài ngắn khác nhau vẫn chiếm đúng
    /// 2 dòng (`reservesSpace`), và luôn dùng một `ProgressView` kiểu `.linear` — kể cả khi chưa có
    /// phần trăm (`value: nil` = vô định) — nên đổi thông báo không còn làm giật khung hình.
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

    private var createSection: some View {
        Section {
            Button {
                let container = modelContext.container
                let selected = scopes
                Task { await coordinator.createBackup(container: container, scopes: selected) }
            } label: {
                Label("Tạo bản sao lưu ngay", systemImage: "arrow.down.doc")
            }
            .disabled(coordinator.isBusy)

            Button {
                showingImporter = true
            } label: {
                Label("Nhập file sao lưu từ Files", systemImage: "folder.badge.plus")
            }
            .disabled(coordinator.isBusy)

            if TelegramConfiguration.isConfigured {
                Button {
                    let container = modelContext.container
                    let selected = scopes
                    Task { await coordinator.createAndSendToTelegram(container: container, scopes: selected) }
                } label: {
                    Label("Tạo và gửi qua Telegram", systemImage: "paperplane.fill")
                }
                .disabled(coordinator.isBusy)
            }
        } footer: {
            Text("Mọi bản sao lưu đều kèm cài đặt & cấu hình của app, gồm quy tắc mục lục và công cụ tra cứu nhanh (trừ khoá API và token); luật thay ký tự TTS đi theo nhóm Custom VietPhrase / Names. Khôi phục là gộp vào dữ liệu hiện có: truyện, kho, extension đã có trong máy được giữ nguyên, chỉ thêm phần còn thiếu.")
        }
    }

    private var driveSection: some View {
        Section {
            NavigationLink {
                GoogleDriveBackupListView(coordinator: coordinator)
            } label: {
                HStack {
                    Label("Google Drive", systemImage: "externaldrive.badge.icloud")
                    Spacer()
                    Text(driveStateText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            NavigationLink {
                TelegramBackupSettingsView()
            } label: {
                HStack {
                    Label("Telegram Bot", systemImage: "paperplane")
                    Spacer()
                    Text(TelegramConfiguration.isConfigured ? "Đã cấu hình" : "Chưa cấu hình")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            NavigationLink {
                DriveAutoBackupSettingsView()
            } label: {
                HStack {
                    Label("Tự động sao lưu", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text(autoBackupStateText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var autoBackupStateText: String {
        DriveAutoBackupPolicy.hasEnabledDestination ? "Đang bật" : "Đang tắt"
    }

    private var driveStateText: String {
        guard GoogleDriveConfiguration.isConfigured else { return "Chưa cấu hình" }
        return coordinator.isDriveSignedIn ? "Đã đăng nhập" : "Chưa đăng nhập"
    }

    // MARK: - Sheet

    private var importer: some View {
        DocumentPicker(
            allowedContentTypes: [Self.archiveType, Self.manifestType, .data],
            allowsMultipleSelection: true,
            onPick: { urls in
                showingImporter = false
                Task { await coordinator.importFromFiles(urls: urls) }
            },
            onCancel: { showingImporter = false }
        )
    }

    @ViewBuilder
    private var restoreSheet: some View {
        if let prepared = coordinator.preparedRestore {
            RestoreOptionsSheet(
                sourceName: restoreSourceName,
                manifest: prepared.manifest,
                onConfirm: runRestore,
                onCancel: { showingRestoreOptions = false }
            )
        } else {
            // Khung xương, **không** phải `ProgressView` trần: sheet được trình bày ngay từ cú chạm đầu
            // (xem `startRestore`) nên đây là thứ người dùng nhìn suốt thời gian giải nén. Khung xương sao
            // đúng bố cục màn thật để lúc `preparedRestore` tới thì chỉ có chữ hiện ra, không có khung nhảy.
            RestoreSkeletonView(sourceName: restoreSourceName) { showingRestoreOptions = false }
        }
    }

    // MARK: - Hành động

    /// Trình bày sheet **ngay**, rồi mới chuẩn bị ở nền.
    ///
    /// `prepareRestore` giải nén archive và đọc `manifest.json` — vài trăm ms tới vài giây với file lớn.
    /// Trước 1.3.475 sheet chỉ được bật **sau khi** việc đó xong, nên suốt khoảng thời gian ấy người dùng
    /// không thấy gì ngoài cú chạm: nút như không phản hồi. Nay sheet hiện tức thì với khung xương.
    private func startRestore(_ item: LocalBackupStore.Item) {
        // Hàng "Khôi phục từ bản này" đã `.disabled(coordinator.isBusy)`, nhưng vẫn chặn ở đây: nếu
        // `prepareRestore` thoát sớm vì `isBusy` thì `preparedRestore` mãi là `nil` và sheet sẽ nháy mở-rồi-đóng.
        guard !coordinator.isBusy else { return }
        restoreSourceName = item.name
        showingRestoreOptions = true
        Task {
            await coordinator.prepareRestore(from: item.url)
            guard showingRestoreOptions else {
                // Người dùng đã đóng sheet trong lúc chuẩn bị ⇒ dọn thư mục tạm vừa giải nén, nếu không nó
                // nằm lại tới lượt khôi phục sau (đây là cửa mới mở ra vì sheet nay đóng được giữa chừng).
                coordinator.cancelPreparedRestore()
                return
            }
            // Lỗi đọc file: `prepareRestore` đã đặt `lastError`, `MainTabView` hiện toast toàn cục; ở đây chỉ
            // cần đóng khung xương, nếu không người dùng ngồi nhìn skeleton vĩnh viễn.
            guard coordinator.preparedRestore != nil else {
                showingRestoreOptions = false
                return
            }
        }
    }

    private func runRestore(_ options: BackupRestoreWorker.Options) {
        isConfirmingRestore = true
        showingRestoreOptions = false
        let container = modelContext.container
        Task { await coordinator.runRestore(container: container, options: options) }
    }

    /// Đóng sheet mà chưa khôi phục thì dọn thư mục tạm; đã bấm khôi phục thì để worker tự dọn.
    private func discardPreparedRestore() {
        guard !isConfirmingRestore else {
            isConfirmingRestore = false
            return
        }
        coordinator.cancelPreparedRestore()
    }
}
