import SwiftUI

struct BookDetailActionSheetModifier: ViewModifier {
    @Binding var selectedBookForTask: Book?
    let selectedTaskType: TaskType
    @Binding var showingBypassBrowser: Bool
    let initialDetailUrl: String
    let resolvedHost: String?
    let onImport: (String, String, String) -> Void

    func body(content: Content) -> some View {
        content
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

extension View {
    func bookDetailActionSheets(
        selectedBookForTask: Binding<Book?>,
        selectedTaskType: TaskType,
        showingBypassBrowser: Binding<Bool>,
        initialDetailUrl: String,
        resolvedHost: String?,
        onImport: @escaping (String, String, String) -> Void
    ) -> some View {
        self.modifier(
            BookDetailActionSheetModifier(
                selectedBookForTask: selectedBookForTask,
                selectedTaskType: selectedTaskType,
                showingBypassBrowser: showingBypassBrowser,
                initialDetailUrl: initialDetailUrl,
                resolvedHost: resolvedHost,
                onImport: onImport
            )
        )
    }
}
