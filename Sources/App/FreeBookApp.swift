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

            if translationManager.isInitialized && ttsPresentation.snapshot.showFloatingWidget {
                TTSFloatingWidgetView()
                    .zIndex(9999)
            }
        }
        .globalToast()
        .sheet(isPresented: Binding(
            get: { ttsPresentation.snapshot.showingSettingsSheet },
            set: { TTSManager.shared.showingSettingsSheet = $0 }
        )) {
            TTSSettingsSheet()
        }
        .onAppear {
            BookStorageManager.shared.drainRetryQueue()
            BookStorageManager.shared.retryFailedChapterStoreDeletions()
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
                }
            }
        }
    }
}
