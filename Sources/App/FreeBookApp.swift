import SwiftUI
import SwiftData

@main
struct FreeBookApp: App {
    let container: ModelContainer

    init() {
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
            fatalError("Không thể khởi tạo ModelContainer: \(error.localizedDescription)")
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
    @ObservedObject private var translationManager = TranslationManager.shared
    @ObservedObject private var ttsManager = TTSManager.shared

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

            if translationManager.isInitialized && ttsManager.showFloatingWidget {
                TTSFloatingWidgetView()
                    .zIndex(9999)
            }
        }
        .globalToast()
        .sheet(isPresented: $ttsManager.showingSettingsSheet) {
            TTSSettingsSheet()
        }
        .onAppear {
            BookStorageManager.shared.drainRetryQueue()
        }
    }
}
