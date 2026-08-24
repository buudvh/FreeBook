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
        .tint(.accentColor)
        .toolbarBackground(.visible, for: .tabBar)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openCurrentlyPlayingReader"))) { _ in
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("sourceChangedNavigateToShelf"))) { _ in
            selectedTab = 0
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
        }
        .task {
            await runAutoDriveBackupIfDue(container: modelContext.container)
        }
        .task {
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
    /// Lượt **tự động** sao lưu lên Google Drive. Cửa mở/đóng thuộc `DriveAutoBackupPolicy`; ở đây
    /// chỉ có việc hoãn cho qua lúc khởi động rồi hiện đúng một toast cho kết quả — service không
    /// được gọi `ToastManager`.
    func runAutoDriveBackupIfDue(container: ModelContainer) async {
        guard DriveAutoBackupPolicy.shouldRun() else { return }
        try? await Task.sleep(nanoseconds: DriveAutoBackupPolicy.startupDelayNanoseconds)
        guard !Task.isCancelled else { return }

        switch await BackupCoordinator.shared.runAutoDriveBackup(container: container) {
        case .skipped:
            break
        case .succeeded(_, let size, _, _):
            ToastManager.shared.show(message: "Đã tự động sao lưu lên Google Drive (\(size))", type: .success)
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
        guard !Task.isCancelled else { return }

        switch await StaleBookCleanupCoordinator.runIfDue(container: container) {
        case .skipped:
            break
        case .deleted(let count):
            ToastManager.shared.show(message: "Đã tự động xoá \(count) truyện lâu không đọc", type: .info)
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
