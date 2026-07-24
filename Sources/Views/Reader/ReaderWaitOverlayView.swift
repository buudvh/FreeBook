import SwiftUI

struct ReaderWaitOverlayView: View {
    @ObservedObject private var manager = WaitLayerManager.shared

    private var displayedBookTitle: String {
        let raw = manager.bookTitle ?? ""
        guard !raw.isEmpty else { return "" }
        return manager.isTranslationEnabled && TranslateUtils.containsChinese(raw)
            ? TranslateUtils.translateChapterTitle(raw, bookId: manager.bookId)
            : raw
    }

    private var displayedChapterTitle: String {
        let raw = manager.chapterTitle ?? ""
        guard !raw.isEmpty else { return "" }
        return manager.isTranslationEnabled && TranslateUtils.containsChinese(raw)
            ? TranslateUtils.translateChapterTitle(raw, bookId: manager.bookId)
            : raw
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            manager.theme.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 12) {
                    if !displayedBookTitle.isEmpty {
                        Text(DisplayTextFormatter.titleCase(displayedBookTitle))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(manager.theme.textColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }

                    if !displayedChapterTitle.isEmpty {
                        Text(displayedChapterTitle)
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(manager.theme.textColor.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 28)

                ProgressView()
                    .controlSize(.large)
                    .tint(manager.theme.textColor)
                    .padding(.top, 4)

                if let statusText = manager.statusText, !statusText.isEmpty {
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(manager.theme.textColor.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Nút Quay lại (Back) góc trên bên trái
            Button(action: {
                let handler = manager.onBackHandler
                manager.close()
                handler?()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(manager.theme.textColor)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(manager.theme.textColor.opacity(0.12)))
            }
            .padding(.leading, 16)
            .padding(.top, 16)
            .accessibilityLabel("Quay lại")
        }
        .opacity(manager.isShowing ? 1 : 0)
        .allowsHitTesting(manager.isShowing)
        .animation(.easeInOut(duration: 0.2), value: manager.isShowing)
        .zIndex(10000)
    }
}
