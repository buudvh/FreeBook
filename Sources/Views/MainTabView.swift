import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ShelfView()
                .tabItem {
                    Label("Kệ Sách", systemImage: "books.vertical.fill")
                }
                .tag(0)
            
            SearchView()
                .tabItem {
                    Label("Tìm Kiếm", systemImage: "magnifyingglass")
                }
                .tag(1)
            
            DiscoveryView()
                .tabItem {
                    Label("Khám Phá", systemImage: "safari.fill")
                }
                .tag(2)
            
            RepositoryManagerView()
                .tabItem {
                    Label("Tiện Ích", systemImage: "puzzlepiece.extension.fill")
                }
                .tag(3)
        }
        .tint(.accentColor)
    }
}

#Preview {
    MainTabView()
}
