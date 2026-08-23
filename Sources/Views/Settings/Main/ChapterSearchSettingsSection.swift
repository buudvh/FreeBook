import SwiftUI

/// Section mở màn cấu hình chỉ mục tìm toàn văn trong màn Cài Đặt.
struct ChapterSearchSettingsSection: View {
    var body: some View {
        Section(header: Text("Tìm Kiếm")) {
            NavigationLink(destination: ChapterSearchIndexSettingsView()) {
                Label("Tìm trong nội dung", systemImage: "text.magnifyingglass")
            }
        }
    }
}
