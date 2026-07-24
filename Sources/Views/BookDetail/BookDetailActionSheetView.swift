import SwiftUI

struct BookDetailActionSheetView: View {
    @Binding var selectedBookForTask: Book?
    let selectedTaskType: TaskType
    @Binding var showingBypassBrowser: Bool
    let initialDetailUrl: String
    let resolvedHost: String?
    let onImport: (String, String, String) -> Void

    var body: some View {
        EmptyView()
            .sheet(item: $selectedBookForTask) { book in
                TaskOptionsSheet(
                    book: book,
                    taskType: selectedTaskType
                )
            }
            .fullScreenCover(isPresented: $showingBypassBrowser) {
                BypassWebView(
                    urlString: initialDetailUrl,
                    host: resolvedHost,
                    onImport: { detailUrl, packageId, sourceName in
                        onImport(detailUrl, packageId, sourceName)
                    }
                )
            }
    }
}
