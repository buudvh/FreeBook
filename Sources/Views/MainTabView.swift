import Combine
import SwiftData
import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    /// Số truyện có chương mới, hiện trên tab Kệ Sách.
    @ObservedObject private var newChapters = NewChapterInboxManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            ShelfView()
                .tabItem {
                    Label("Kệ Sách", systemImage: "books.vertical.fill")
                }
                .badge(newChapters.totalNewBooks)
                .tag(0)
            
            DiscoveryView()
                .tabItem {
                    Label("Khám Phá", systemImage: "safari.fill")
                }
                .tag(1)
            
            RepositoryManagerView()
                .tabItem {
                    Label("Tiện Ích", systemImage: "puzzlepiece.extension.fill")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label("Cài Đặt", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.white)
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
        .toolbarBackground(.visible, for: .tabBar)
        // Kết quả sao lưu / khôi phục và kết quả tải model — hai nguồn kết quả tác vụ **nền**: hiện toast ở
        // **đây** (root, luôn sống) để không phụ thuộc việc người dùng còn đang đứng ở màn bấm hay không, kể cả
        // lượt bấm từ màn Google Drive. `BackupHubView` đã gỡ observer của nó để một lượt không hiện hai toast.
        // Chỉ nghe đúng ba publisher thay vì observe cả hai object: `progress` của backup và tiến độ tải model
        // publish liên tục, observe cả object là vẽ lại root theo từng nhịp. `@Published` phát lúc willSet nên
        // phải `receive(on:)` sang lượt main kế tiếp rồi mới xoá về nil — xoá ngay sẽ bị setter ngoài ghi đè.
        // Guard "giá trị vẫn còn nguyên" giữ đúng ngữ nghĩa `onChange` cũ: giá trị đã bị thay/được nơi khác
        // xử lý (vd `DriveAutoBackupSettingsView` cũng tiêu thụ `lastError`) thì không hiện thêm toast.
        .onReceive(BackupCoordinator.shared.$lastMessage.compactMap { $0 }.receive(on: DispatchQueue.main)) { message in
            guard BackupCoordinator.shared.lastMessage == message else { return }
            ToastManager.shared.show(message: message, type: .success)
            BackupCoordinator.shared.lastMessage = nil
        }
        .onReceive(BackupCoordinator.shared.$lastError.compactMap { $0 }.receive(on: DispatchQueue.main)) { error in
            guard BackupCoordinator.shared.lastError == error else { return }
            ToastManager.shared.show(message: error, type: .error)
            BackupCoordinator.shared.lastError = nil
        }
        .onReceive(ModelDownloadCenter.shared.$lastNotice.compactMap { $0 }.receive(on: DispatchQueue.main)) { notice in
            guard ModelDownloadCenter.shared.lastNotice == notice else { return }
            ToastManager.shared.show(message: notice.message, type: notice.isError ? .error : .success)
            ModelDownloadCenter.shared.clearNotice()
        }
        // Widget thông báo nổi phải biết tab đang chọn để tự ẩn ở tab Kệ Sách (tab đó đã có nút chuông ở
        // toolbar). `selectedTab` là `@State` cục bộ nên không ai đọc được — phát ra ngoài bằng notification.
        .onChange(of: selectedTab) { _, index in
            NotificationCenter.default.post(
                name: .appTabDidChange,
                object: nil,
                userInfo: [NotificationFloatingWidgetWindowManager.tabIndexUserInfoKey: index]
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openCurrentlyPlayingReader"))) { _ in
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("sourceChangedNavigateToShelf"))) { _ in
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("navigateToSettingsTab"))) { _ in
            selectedTab = 3
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task {
                await ChapterContentRepository.shared.trimMemoryCache()
            }
        }
        .onAppear {
            DownloadManager.shared.initialize(container: modelContext.container)
            TTSManager.shared.initialize(container: modelContext.container)
            Task {
                await ReadingProgressStore.shared.configure(container: modelContext.container)
                await ChapterContentRepository.shared.configure(container: modelContext.container)
                await NotificationInboxManager.shared.loadIfNeeded()
            }
            Self.cleanupLegacyChapterSearchIndex()
            // Bản nháp debug là dữ liệu tạm: không được sống qua một lần chạy app.
            Task { await ExtensionDraftStagingStore.shared.discardAll() }
            // Công tắc debug server sống lâu hơn màn hình: mở lại app thì theo lựa chọn cũ.
            ExtensionDebugServerLauncher.restoreIfEnabled(container: modelContext.container)
        }
        // `.utility`: nén + tải lên + dọn truyện là việc nền, không được tranh CPU với Reader/TTS
        // (`.task` mặc định là `.userInitiated`). Bước nhảy MainActor bên trong vẫn chạy trên main.
        .task(priority: .utility) {
            await runAutomaticBackupIfDue(container: modelContext.container)
        }
        .task(priority: .utility) {
            await runStaleBookCleanupIfDue(container: modelContext.container)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Bản xuất hoàn thành lúc app ở background: share sheet không trình bày được, được giữ lại
                // và bàn giao ngay khi app trở lại foreground.
                ExportShareCoordinator.shared.flushPendingShare()
                return
            }
            guard phase == .inactive || phase == .background else { return }
            TTSManager.shared.checkpointForBackground()
            let backgroundSession = BackgroundTaskSession.begin(name: "Flush reading progress")
            Task(priority: .high) {
                try? await ReadingProgressStore.shared.flushAll()
                await ChapterContentRepository.shared.flushAll()
                backgroundSession.end()
            }
        }
    }
}

extension MainTabView {
    /// Lượt tự động sao lưu tới các đích đã bật. Cửa mở/đóng thuộc `DriveAutoBackupPolicy`; ở đây
    /// chỉ có việc hoãn cho qua lúc khởi động rồi hiện đúng một toast cho kết quả — service không
    /// được gọi `ToastManager`.
    func runAutomaticBackupIfDue(container: ModelContainer) async {
        guard DriveAutoBackupPolicy.shouldRun() else { return }
        try? await Task.sleep(nanoseconds: DriveAutoBackupPolicy.startupDelayNanoseconds)
        guard !Task.isCancelled else { return }

        let outcome: BackupCoordinator.AutoDriveBackupOutcome
        switch await BackupCoordinator.shared.runScheduledAutoBackup(container: container) {
        case .unchanged:
            // Không có gì đổi kể từ lượt thành công gần nhất: im lặng như `.notDue`.
            return
        case .ran(let ran):
            outcome = ran
        }
        switch outcome {
        case .skipped(.notDue):
            break
        case .skipped(.driveNotLinked):
            // Tới kỳ mà chưa đăng nhập: im lặng thì lượt tự động không bao giờ chạy mà người dùng
            // không hề biết. Policy đã giới hạn nhịp nhắc nên đây không thành toast mỗi lần mở app.
            ToastManager.shared.show(message: "Tự động sao lưu đang bật nhưng chưa đăng nhập Google Drive", type: .error)
        case .skipped(.telegramNotConfigured):
            ToastManager.shared.show(message: "Tự động sao lưu đang bật nhưng chưa cấu hình Telegram", type: .error)
        case .completed(_, let size, let driveSent, let telegramSent, let failures, _, _, let pruneIncomplete):
            let destinations = [driveSent ? "Drive" : nil, telegramSent ? "Telegram" : nil]
                .compactMap { $0 }.joined(separator: " và ")
            let failureNote = failures.isEmpty ? "" : " — " + failures.joined(separator: "; ")
            ToastManager.shared.show(
                message: "Đã tự động sao lưu (\(size))" + (destinations.isEmpty ? "" : " tới \(destinations)")
                    + failureNote + outcome.pruneNote,
                type: failures.isEmpty && !pruneIncomplete ? .success : .info
            )
        case .failed(let message):
            ToastManager.shared.show(message: "Tự động sao lưu thất bại: \(message)", type: .error)
        }
    }

    /// Lượt **tự động** dọn truyện lâu không đọc. Cửa mở/đóng thuộc `StaleBookCleanupPolicy` (mặc định
    /// tắt); hoãn lâu hơn lượt sao lưu để bản sao lưu chạy trước khi có gì bị xoá. Toast chỉ hiện khi
    /// thật sự xoá được truyện hoặc khi lỗi — service không được gọi `ToastManager`.
    func runStaleBookCleanupIfDue(container: ModelContainer) async {
        guard StaleBookCleanupPolicy.shouldRun() else { return }
        try? await Task.sleep(nanoseconds: StaleBookCleanupPolicy.startupDelayNanoseconds)
        // Hoãn theo giờ chưa đủ: lượt sao lưu (hoặc khôi phục/tải lên bấm tay) có thể còn chạy quá mốc trên.
        // Chờ nó xong để bản sao lưu chụp trước khi có gì bị xoá — kiểm tra mỗi 2 s, tối đa ~10 phút.
        var busyPolls = 0
        while BackupCoordinator.shared.isBusy, !Task.isCancelled, busyPolls < 300 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            busyPolls += 1
        }
        guard !Task.isCancelled else { return }

        switch await StaleBookCleanupCoordinator.runIfDue(container: container) {
        case .skipped:
            break
        case .deleted(let count):
            ToastManager.shared.show(message: "Đã tự động xoá \(count) truyện lâu không đọc", type: .success)
        case .failed(let message):
            ToastManager.shared.show(message: "Tự động dọn truyện cũ thất bại: \(message)", type: .error)
        }
    }

    /// Dọn best-effort thư mục chỉ mục tìm toàn văn cũ (`applicationSupportDirectory/search/`) còn
    /// sót của người từng bật bản 1.3.257. Chỉ mục là dữ liệu phái sinh, xoá luôn cho gọn — chạy nền
    /// một lần lúc khởi động, nuốt mọi lỗi vì không ảnh hưởng tính đúng.
    static func cleanupLegacyChapterSearchIndex() {
        Task.detached(priority: .background) {
            let fm = FileManager.default
            guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
            let legacyDir = appSupport.appendingPathComponent("search", isDirectory: true)
            guard fm.fileExists(atPath: legacyDir.path) else { return }
            try? fm.removeItem(at: legacyDir)
        }
    }
}

#Preview {
    MainTabView()
}
