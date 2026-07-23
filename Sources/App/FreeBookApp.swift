import SwiftUI
import SwiftData

public enum LaunchState {
    case loading
    case ready(
        chapterRepository: any ChapterRepositoryProtocol,
        bookStorageManager: BookStorageManager
    )
    case failed(Error)
}

private struct ChapterRepositoryKey: EnvironmentKey {
    static let defaultValue: ChapterRepositoryProtocol = ChapterSQLiteRepository()
}

public extension EnvironmentValues {
    var chapterRepository: ChapterRepositoryProtocol {
        get { self[ChapterRepositoryKey.self] }
        set { self[ChapterRepositoryKey.self] = newValue }
    }
}

@main
struct FreeBookApp: App {
    let container: ModelContainer
    @State private var launchState: LaunchState = .loading

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
                DownloadTaskModel.self,
                configurations: config
            )
        } catch {
            fatalError("Không thể khởi tạo ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchRootView(launchState: $launchState)
                .task {
                    await loadAppDependencies()
                }
        }
        .modelContainer(container)
    }

    private func loadAppDependencies() async {
        guard case .ready = launchState else {
            launchState = .loading
            do {
                let repo = try await ChapterRepositoryFactory.make()
                let storageManager = BookStorageManager(chapterRepository: repo)
                launchState = .ready(chapterRepository: repo, bookStorageManager: storageManager)
            } catch {
                launchState = .failed(error)
            }
            return
        }
    }
}

struct AppLaunchRootView: View {
    @Binding var launchState: LaunchState
    @ObservedObject private var translationManager = TranslationManager.shared
    @ObservedObject private var ttsManager = TTSManager.shared

    var body: some View {
        ZStack {
            switch launchState {
            case .loading:
                AppLoadingView()
                    .transition(.opacity)

            case .failed(let error):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("Không thể khởi tạo CSDL")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Thử lại") {
                        Task {
                            launchState = .loading
                            do {
                                let repo = try await ChapterRepositoryFactory.make()
                                let storageManager = BookStorageManager(chapterRepository: repo)
                                launchState = .ready(chapterRepository: repo, bookStorageManager: storageManager)
                            } catch {
                                launchState = .failed(error)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .ready(let repo, let manager):
                Group {
                    if translationManager.isInitialized {
                        MainTabView()
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        AppLoadingView()
                            .transition(.opacity)
                    }
                }
                .environment(\.chapterRepository, repo)
                .environment(\.bookStorageManager, manager)
                .animation(.easeInOut(duration: 0.5), value: translationManager.isInitialized)
            }

            if case .ready = launchState, translationManager.isInitialized && ttsManager.showFloatingWidget {
                TTSFloatingWidgetView()
                    .zIndex(999)
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
