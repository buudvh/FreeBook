import SwiftUI

struct ReaderViewModelObserver<Content: View>: View {
    @ObservedObject var viewModel: ReaderViewModel
    let content: (ReaderViewModel) -> Content

    init(
        viewModel: ReaderViewModel,
        @ViewBuilder content: @escaping (ReaderViewModel) -> Content
    ) {
        self.viewModel = viewModel
        self.content = content
    }

    var body: some View {
        content(viewModel)
    }
}
