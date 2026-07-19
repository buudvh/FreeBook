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
            Chapter.self,
            DownloadTaskModel.self
        ])
    }
}

struct AppLaunchRootView: View {
    @ObservedObject private var translationManager = TranslationManager.shared
    @ObservedObject private var ttsManager = TTSManager.shared
    @ObservedObject private var toastManager = ToastManager.shared
    
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
                    .zIndex(999)
            }
            
            // Global Toast Notification
            if toastManager.showingToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        switch toastManager.toastType {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .error:
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                        case .info:
                            EmptyView()
                        }
                        
                        Text(toastManager.toastMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.1).opacity(0.92))
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    )
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.25), value: toastManager.showingToast)
                .zIndex(1000)
            }
        }
        // Sheet cài đặt TTS toàn cục – hoạt động ở mọi tab và màn hình
        .sheet(isPresented: $ttsManager.showingSettingsSheet) {
            TTSSettingsSheet()
        }
    }
}
