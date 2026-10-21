import SwiftData
import SwiftUI

/// Gắn presenter của engine nguồn Legado (`LegadoPresentationPresenter`) vào view gốc: một `.task` sống suốt đời app,
/// cạnh các subscriber `TTSPresentationEventCenter` / `DownloadPresentationEventCenter` của `AppLaunchRootView`.
/// Chỉ gắn **một lần** — stream của engine chỉ có một người đọc.
struct LegadoPresentationHandler: ViewModifier {
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .task {
                await LegadoPresentationPresenter.shared.run(container: modelContext.container)
            }
    }
}

extension View {
    /// Presenter trình duyệt / mã xác minh / sự kiện của nguồn Legado — xem `LegadoPresentationHandler`.
    func legadoPresentationHandler() -> some View {
        modifier(LegadoPresentationHandler())
    }
}
