import SwiftUI
import SwiftData
import UIKit

@main
struct FreeBookApp: App {
    let container: ModelContainer

    init() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        NavigationBarAppearance.applyTitlelessBackButton()

        do {
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            let dbURL = appSupportURL.appendingPathComponent("library.db")
            let config = ModelConfiguration(url: dbURL)
            container = try ModelContainer(
                for: Repository.self,
                Extension.self,
                Book.self,
                Chapter.self,
                DownloadTaskModel.self,
                configurations: config
            )
        } catch {
            fatalError("Không thể khởi tạo ModelContainer: \(error.localizedDescription) ")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchRootView()
        }
        .modelContainer(container)
    }
}

struct AppLaunchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var translationManager = TranslationManager.shared
    @StateObject private var ttsPresentation = TTSRootPresentationReader()
    @StateObject private var browserPresentation = VisibleBrowserPresentationReader()

    var body: some View {
        ZStack {
            Group {
                if translationManager.isInitialized {
                    MainTabView()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    AppLoadingView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: translationManager.isInitialized)
        }
        .onAppear {
            KeyboardDismissGesture.shared.activate()
            BookStorageManager.shared.drainRetryQueue()
            BookStorageManager.shared.retryFailedChapterStoreDeletions()
            TTSFloatingWidgetWindowManager.shared.modelContainer = modelContext.container
            TTSFloatingWidgetWindowManager.shared.refreshState()
            BrowserFloatingWidgetWindowManager.shared.refreshState()
        }
        .onChange(of: translationManager.isInitialized) { _, _ in
            TTSFloatingWidgetWindowManager.shared.modelContainer = modelContext.container
            TTSFloatingWidgetWindowManager.shared.refreshState()
            BrowserFloatingWidgetWindowManager.shared.refreshState()
        }
        .onChange(of: browserPresentation.snapshot.showReopenButton) { _, _ in
            BrowserFloatingWidgetWindowManager.shared.refreshState()
        }
        .onChange(of: ttsPresentation.snapshot.showFloatingWidget) { _, _ in
            TTSFloatingWidgetWindowManager.shared.modelContainer = modelContext.container
            TTSFloatingWidgetWindowManager.shared.refreshState()
        }
        .task(id: translationManager.isInitialized) {
            TTSFloatingWidgetWindowManager.shared.modelContainer = modelContext.container
            guard translationManager.isInitialized else { return }
            // Backfill tên dịch/phương âm cho các sách chưa có (titleTrans/authorTrans),
            // chạy sau khi từ điển đã nạp — mirror pattern nạp dict ban đầu.
            await BookTitleTranslationMigrator.runIfNeeded(container: modelContext.container)
        }
        .task {
            for await event in TTSPresentationEventCenter.shared.stream {
                switch event {
                case .showToast(let msg, let type):
                    ToastManager.shared.show(message: msg, type: type)
                }
            }
        }
        .task {
            for await event in DownloadPresentationEventCenter.shared.stream {
                switch event {
                case .showToast(let msg, let type):
                    ToastManager.shared.show(message: msg, type: type)
                case .exportReady(let filePath, let bookTitle):
                    ExportShareCoordinator.shared.requestShare(filePath: filePath, bookTitle: bookTitle)
                }
            }
        }
    }
}
