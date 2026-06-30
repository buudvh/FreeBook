import SwiftUI
import SwiftData

@main
struct FreeBookApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: [
            Repository.self,
            Extension.self,
            Book.self,
            Chapter.self
        ])
    }
}
