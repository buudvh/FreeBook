import SwiftUI

struct ReaderWaitOverlayView: View {
    let bookTitle: String?
    let chapterTitle: String?
    let isTranslationEnabled: Bool
    let bookId: String
    let theme: ReaderTheme
    var statusText: String? = nil
    let onBack: () -> Void

    private var displayedBookTitle: String {
        let raw = bookTitle ?? ""
        guard !raw.isEmpty else { return "" }
        return isTranslationEnabled && TranslateUtils.containsChinese(raw)
            ? TranslateUtils.translateChapterTitle(raw, bookId: bookId)
            : raw
    }

    private var displayedChapterTitle: String {
        let raw = chapterTitle ?? ""
        guard !raw.isEmpty else { return "" }
        return isTranslationEnabled && TranslateUtils.containsChinese(raw)
            ? TranslateUtils.translateChapterTitle(raw, bookId: bookId)
            : raw
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 12) {
                    if !displayedBookTitle.isEmpty {
                        Text(DisplayTextFormatter.titleCase(displayedBookTitle))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(theme.textColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }

                    if !displayedChapterTitle.isEmpty {
                        Text(displayedChapterTitle)
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(theme.textColor.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 28)

                ProgressView()
                    .controlSize(.large)
                    .tint(theme.textColor)
                    .padding(.top, 4)

                if let statusText, !statusText.isEmpty {
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(theme.textColor.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Nút Quay lại (Back) góc trên bên trái
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.textColor)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.textColor.opacity(0.12)))
            }
            .padding(.leading, 16)
            .padding(.top, 16)
            .accessibilityLabel("Quay lại")
        }
        .transition(.opacity)
        .zIndex(100)
    }
}
