import SwiftUI
import Combine

@MainActor
public final class WaitLayerManager: ObservableObject {
    public static let shared = WaitLayerManager()

    @Published public private(set) var isShowing: Bool = false
    @Published public private(set) var bookTitle: String? = nil
    @Published public private(set) var chapterTitle: String? = nil
    @Published public private(set) var isTranslationEnabled: Bool = false
    @Published public private(set) var bookId: String = ""
    @Published public private(set) var theme: ReaderTheme = .dark
    @Published public private(set) var statusText: String? = nil
    public var onBackHandler: (() -> Void)? = nil

    private init() {}

    public func open(
        bookTitle: String?,
        chapterTitle: String?,
        isTranslationEnabled: Bool = false,
        bookId: String = "",
        theme: ReaderTheme = .dark,
        statusText: String? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.bookTitle = bookTitle
        self.chapterTitle = chapterTitle
        self.isTranslationEnabled = isTranslationEnabled
        self.bookId = bookId
        self.theme = theme
        self.statusText = statusText
        self.onBackHandler = onBack
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isShowing = true
        }
    }

    public func close() {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isShowing = false
        }
        self.onBackHandler = nil
    }
}
