import SwiftUI
import SwiftData

@main
struct FreeBookApp: App {
    var body: some Scene {
        WindowGroup {
            AppLaunchRootView()
        }
        .modelContainer(for: [
            Repository.self,
            Extension.self,
            Book.self,
            Chapter.self
        ])
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
            
            if translationManager.isInitialized && ttsManager.showFloatingWidget {
                TTSFloatingWidgetView()
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: translationManager.isInitialized)
    }
}
