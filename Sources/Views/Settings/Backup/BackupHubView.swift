import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Màn Sao lưu & Khôi phục: chọn nhóm nội dung, tạo file `.fbbackup`, quản lý bản trong máy,
/// nhập file từ Files và mở tab Google Drive.
///
/// Mọi ghi dữ liệu đi qua `BackupCoordinator` (View không chạm `modelContext.insert/save`).
/// Chặn khôi phục khi TTS đang phát — đọc trạng thái qua projection reader, không observe
/// `TTSManager` trực tiếp.
struct BackupHubView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var coordinator = BackupCoordinator.shared
    @StateObject private var ttsState = TTSWidgetStateReader()

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

    var body: some View {
        List {
            if coordinator.progress.isActive {
                progressSection
            }

            BackupScopeToggleList(selection: $scopes)
            createSection

            LocalBackupListView(
                coordinator: coordinator,
                isTTSPlaying: ttsState.snapshot.isPlaying,
                canUploadToDrive: GoogleDriveConfiguration.isConfigured && coordinator.isDriveSignedIn,
                onRestore: startRestore,
                onShare: { sharingItem = $0 },
                onUpload: { item in Task { await coordinator.uploadToDrive(item) } }
            )

            driveSection
        }
        .navigationTitle("Sao Lưu & Khôi Phục")
        .onAppear { coordinator.refreshLocal() }
        .sheet(isPresented: $showingImporter) { importer }
        .sheet(item: $sharingItem) { ShareSheet(activityItems: [$0.url]) }
        .sheet(isPresented: $showingRestoreOptions, onDismiss: discardPreparedRestore) { restoreSheet }
        .onChange(of: coordinator.lastMessage) { _, message in
            guard let message else { return }
            ToastManager.shared.show(message: message, type: .success)
            coordinator.lastMessage = nil
        }
        .onChange(of: coordinator.lastError) { _, error in
            guard let error else { return }
            ToastManager.shared.show(message: error, type: .error)
            coordinator.lastError = nil
        }
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
        } footer: {
            Text(ttsState.snapshot.isPlaying
                 ? "Đang phát TTS — hãy dừng phát trước khi khôi phục. Việc tạo bản sao lưu vẫn được."
                 : "Khôi phục là gộp vào dữ liệu hiện có: truyện, kho, extension đã có trong máy được giữ nguyên, chỉ thêm phần còn thiếu.")
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
        }
    }

    private var driveStateText: String {
        guard GoogleDriveConfiguration.isConfigured else { return "Chưa cấu hình" }
        return coordinator.isDriveSignedIn ? "Đã đăng nhập" : "Chưa đăng nhập"
    }

    // MARK: - Sheet

    private var importer: some View {
        DocumentPicker(
            allowedContentTypes: [Self.archiveType],
            allowsMultipleSelection: false,
            onPick: { urls in
                guard let url = urls.first else { return }
                coordinator.importFromFiles(url: url)
            },
            onCancel: nil
        )
    }

    @ViewBuilder
    private var restoreSheet: some View {
        if let prepared = coordinator.preparedRestore {
            RestoreOptionsSheet(
                sourceName: restoreSourceName,
                manifest: prepared.manifest,
                isTTSPlaying: ttsState.snapshot.isPlaying,
                onConfirm: runRestore,
                onCancel: { showingRestoreOptions = false }
            )
        } else {
            ProgressView("Đang đọc file sao lưu…")
        }
    }

    // MARK: - Hành động

    private func startRestore(_ item: LocalBackupStore.Item) {
        guard !ttsState.snapshot.isPlaying else {
            ToastManager.shared.show(message: "Hãy dừng phát TTS trước khi khôi phục", type: .error)
            return
        }
        restoreSourceName = item.name
        Task {
            await coordinator.prepareRestore(from: item.url)
            guard coordinator.preparedRestore != nil else { return }
            showingRestoreOptions = true
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
