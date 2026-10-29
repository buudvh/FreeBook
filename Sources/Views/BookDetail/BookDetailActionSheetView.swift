import SwiftUI

struct BookDetailActionSheetModifier: ViewModifier {
    /// Sheet tải/xuất — sách + loại tác vụ đi chung một item (`TaskSheetRequest`, 1.3.654).
    @Binding var taskSheetRequest: TaskSheetRequest?
    @Binding var showingBypassBrowser: Bool
    let initialDetailUrl: String
    let resolvedHost: String?
    let onImport: (String, String, String) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $taskSheetRequest) { request in
                TaskOptionsSheet(
                    book: request.book,
                    taskType: request.taskType
                )
            }
            .fullScreenCover(isPresented: $showingBypassBrowser) {
                BypassWebView(
                    urlString: initialDetailUrl,
                    host: resolvedHost,
                    onImport: { detailUrl, packageId, sourceName in
                        showingBypassBrowser = false
                        onImport(detailUrl, packageId, sourceName)
                    }
                )
            }
    }
}

extension View {
    func bookDetailActionSheets(
        taskSheetRequest: Binding<TaskSheetRequest?>,
        showingBypassBrowser: Binding<Bool>,
        initialDetailUrl: String,
        resolvedHost: String?,
        onImport: @escaping (String, String, String) -> Void
    ) -> some View {
        self.modifier(
            BookDetailActionSheetModifier(
                taskSheetRequest: taskSheetRequest,
                showingBypassBrowser: showingBypassBrowser,
                initialDetailUrl: initialDetailUrl,
                resolvedHost: resolvedHost,
                onImport: onImport
            )
        )
    }
}
