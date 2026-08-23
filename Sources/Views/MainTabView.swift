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
