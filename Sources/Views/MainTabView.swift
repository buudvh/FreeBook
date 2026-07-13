import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ShelfView()
                .tabItem {
                    Label("Kệ Sách", systemImage: "books.vertical.fill")
                }
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openCurrentlyPlayingReader"))) { _ in
            selectedTab = 0
        }
        .onAppear {
            DownloadManager.shared.initialize(container: modelContext.container)
            TTSManager.shared.initialize(container: modelContext.container)
        }
    }
}

#Preview {
    MainTabView()
}
