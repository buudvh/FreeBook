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
                BookCollection.self,
                Chapter.self,
                DownloadTaskModel.self,
                configurations: config
            )
        } catch {
            fatalError("Không thể khởi tạo ModelContainer: \(error.localizedDescription) ")
        }

        // Nâng giới hạn file descriptor + ghi mốc đếm fd ban đầu (chẩn đoán cạn fd sau phiên nghe dài).
        FileDescriptorCensus.start()
        // Bộ ghi nhiệt cho màn "Theo dõi nhiệt": 1 mẫu / 30 giây vào bộ đệm vòng trong RAM, không ghi đĩa.
        DeviceThermalMonitor.shared.start()
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
            // Compile bộ rule dịch trước khi lần dịch đầu chạy: `AppLaunchRootView` chặn app tới khi
            // từ điển nạp xong, nên đây là chỗ sớm nhất mà snapshot chắc chắn sẵn sàng trước Reader.
            Task.detached(priority: .utility) {
                QuickTranslationRuleStore.shared.prewarm()
            }
            BookStorageManager.shared.drainRetryQueue()
            BookStorageManager.shared.retryFailedChapterStoreDeletions()
            // `Extension.localPath` là path tuyệt đối: gốc thư mục dữ liệu đổi thì trỏ lại thư mục thật trước khi
            // Reader/TTS cần tới (app còn chặn ở màn nạp từ điển). Chỉ sửa path, không gỡ/xoá gì.
            ExtensionTransactionCoordinator.shared.repairExtensionPathsAtLaunch(in: modelContext)
            TTSFloatingWidgetWindowManager.shared.modelContainer = modelContext.container
            TTSFloatingWidgetWindowManager.shared.refreshState()
            // Nút hub nổi (AI / trình duyệt / thông báo): `modelContainer` là bắt buộc vì màn Thông báo được
            // trình bày từ cửa sổ riêng của hub, mà cửa sổ đó không có environment của app. Hub tự nghe các
            // nguồn của nó; root chỉ còn phải gọi lại khi cổng từ điển mở.
            FloatingHubWindowManager.shared.modelContainer = modelContext.container
            FloatingHubWindowManager.shared.refreshState()
        }
        .onChange(of: translationManager.isInitialized) { _, _ in
            TTSFloatingWidgetWindowManager.shared.modelContainer = modelContext.container
            TTSFloatingWidgetWindowManager.shared.refreshState()
            FloatingHubWindowManager.shared.modelContainer = modelContext.container
            FloatingHubWindowManager.shared.refreshState()
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
