import SwiftUI
import SwiftData
import UIKit

@main
struct FreeBookApp: App {
    let container: ModelContainer

    init() {
        // Mặc định chặn quảng cáo/cửa sổ bật lên phải có TRƯỚC mọi chỗ tạo webview (và mọi `@AppStorage` đọc chúng).
        WebContentSettings.registerDefaults()
        RepositoryFilterPolicy.resetNsfwVisibilityOnLaunch()
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        NavigationBarAppearance.applyTitlelessBackButton()

        do {
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            let dbURL = appSupportURL.appendingPathComponent("library.db")
            // Tiện ích & kho đã rời SwiftData sang `extension_store/` (JSON). Phải chuyển dữ liệu cũ TRƯỚC khi
            // mở container: schema mới không còn `Extension`/`Repository`, mở xong SwiftData có thể drop hai bảng.
            LegacyExtensionSQLiteMigrator.runIfNeeded(databaseURL: dbURL)
            ExtensionLibraryRepository.shared.load()
            let config = ModelConfiguration(url: dbURL)
            container = try ModelContainer(
                for: Book.self,
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
        // Liên kết `legado://…` (nhập nguồn Legado) — hỏi lại rồi mới nhập; chờ cổng từ điển mở.
        .legadoLinkImportHandler(isReady: translationManager.isInitialized)
        .onAppear {
            KeyboardDismissGesture.shared.activate()
            // Thanh công cụ trên bàn phím (đóng bàn phím, aa…AA, xoá/sao chép/dán) cho mọi ô nhập.
            KeyboardTextToolbarInstaller.shared.activate()
            // Compile bộ rule dịch trước khi lần dịch đầu chạy: `AppLaunchRootView` chặn app tới khi
            // từ điển nạp xong, nên đây là chỗ sớm nhất mà snapshot chắc chắn sẵn sàng trước Reader.
            Task.detached(priority: .utility) {
                QuickTranslationRuleStore.shared.prewarm()
            }
            BookStorageManager.shared.drainRetryQueue()
            BookStorageManager.shared.retryFailedChapterStoreDeletions()
            TTSFloatingWidgetWindowManager.shared.modelContainer = modelContext.container
            TTSFloatingWidgetWindowManager.shared.refreshState()
            // Nút hub nổi (AI / thông báo / video): `modelContainer` là bắt buộc vì màn Thông báo được
            // trình bày từ cửa sổ riêng của hub, mà cửa sổ đó không có environment của app. Hub tự nghe các
            // nguồn của nó; root chỉ còn phải gọi lại khi cổng từ điển mở.
            FloatingHubWindowManager.shared.modelContainer = modelContext.container
            FloatingHubWindowManager.shared.refreshState()
            // Widget trình duyệt thu nhỏ (cửa sổ riêng, tách khỏi hub ở 1.3.533) tự nghe trạng thái trình duyệt;
            // root chỉ gọi lúc khởi động và khi cổng từ điển mở, như trước khi gộp vào hub.
            BrowserFloatingWidgetWindowManager.shared.refreshState()
        }
        .onChange(of: translationManager.isInitialized) { _, _ in
            TTSFloatingWidgetWindowManager.shared.modelContainer = modelContext.container
            TTSFloatingWidgetWindowManager.shared.refreshState()
            FloatingHubWindowManager.shared.modelContainer = modelContext.container
            FloatingHubWindowManager.shared.refreshState()
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
