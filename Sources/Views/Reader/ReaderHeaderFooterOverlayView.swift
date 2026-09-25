import SwiftUI

struct ReaderHeaderFooterOverlayView: View {
    let selectedTheme: ReaderTheme
    @Binding var isTranslationEnabled: Bool
    @Binding var isAutoScrollDisabled: Bool
    @Binding var showingBookDictionary: Bool
    @Binding var showingBypassBrowser: Bool
    @Binding var showingSettings: Bool
    @Binding var showingChapterList: Bool
    let readerBookDisplayTitle: String
    let readerChapterDisplayTitle: String
    let bookId: String
    let packageId: String
    let sourceName: String
    let hasLocalBook: Bool
    let isLocalTXTBook: Bool
    let chapterIndex: Int
    let pendingNavigationIndex: Int?
    let navigationFailureMessage: String?
    let totalChaptersCount: Int
    let readerPresentedChapterIndex: Int
    let readerProgressPercent: Double

    let onDismiss: () -> Void
    let onReloadChapter: () -> Void
    let onChangeSource: () -> Void
    let onOpenChapterList: () -> Void
    let onOpenReaderSearch: () -> Void
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void
    let onOpenAppSettings: () -> Void
    let onOpenAI: () -> Void

    var readerChromeBackground: Color {
        selectedTheme.backgroundColor
    }

    var body: some View {
        VStack {
            // Header View
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedTheme.textColor)
                            .frame(width: 36, height: 44)
                    }
                    .accessibilityLabel("Quay lại")

                    Spacer()

                    HStack(spacing: 2) {
                        // Tìm trong chương — để cạnh nút cuộn theo TTS thay vì nằm trong menu "..."
                        Button(action: onOpenReaderSearch) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(selectedTheme.textColor)
                                .frame(width: 30, height: 36)
                        }
                        .accessibilityLabel("Tìm trong chương")

                        // Nút toggle tự động cuộn theo Highlight TTS - luôn hiển thị
                        Button(action: { isAutoScrollDisabled.toggle() }) {
                            Image(systemName: isAutoScrollDisabled ? "scroll" : "scroll.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isAutoScrollDisabled ? selectedTheme.textColor.opacity(0.85) : .white)
                                .frame(width: 30, height: 30)
                                .background(selectedTheme.textColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .accessibilityLabel(isAutoScrollDisabled ? "Bật cuộn theo Highlight TTS" : "Tắt cuộn theo Highlight TTS")

                        if !isLocalTXTBook {
                            Button(action: onReloadChapter) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(selectedTheme.textColor)
                                    .frame(width: 30, height: 36)
                            }
                            .accessibilityLabel("Tải lại chương")
                        }

                        Button(action: onOpenAI) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(selectedTheme.textColor)
                                .frame(width: 30, height: 36)
                        }
                        .accessibilityLabel("Trợ lý AI")

                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(selectedTheme.textColor)
                                .frame(width: 30, height: 36)
                        }
                        .accessibilityLabel("Cài đặt trình đọc")

                        Menu {
                            Button(action: onOpenAI) {
                                Label("Trợ lý AI", systemImage: "sparkles")
                            }

                            if hasLocalBook {
                                Button(action: { showingBookDictionary = true }) {
                                    Label("Từ điển truyện", systemImage: "book.closed")
                                }
                            }

                            Button(action: { showingBypassBrowser = true }) {
                                Label("Mở bằng trình duyệt", systemImage: "safari")
                            }

                            if !isLocalTXTBook {
                                Button(action: onChangeSource) {
                                    Label("Đổi nguồn truyện", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }

                            Button(action: onOpenAppSettings) {
                                Label("Mở Cài đặt", systemImage: "gearshape.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(selectedTheme.textColor)
                                .frame(width: 30, height: 36)
                        }
                        .accessibilityLabel("Tùy chọn trình đọc")
                    }
                }

                HStack(alignment: .center, spacing: 8) {
                    ReaderTranslationScopeMenuView(
                        bookId: bookId,
                        packageId: packageId,
                        sourceName: sourceName,
                        textColor: selectedTheme.textColor,
                        showBackground: true
                    )

                    Button(action: onOpenChapterList) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(readerBookDisplayTitle)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(selectedTheme.textColor)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            HStack(spacing: 6) {
                                Text(readerChapterDisplayTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(selectedTheme.textColor.opacity(0.72))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(selectedTheme.textColor.opacity(0.72))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mở danh sách chương, \(readerChapterDisplayTitle)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .background(readerChromeBackground.ignoresSafeArea(edges: .top))

            Spacer()

            // Footer View
            HStack(spacing: 0) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onPrevChapter()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReaderNavPressButtonStyle(highlightColor: selectedTheme.textColor))
                .disabled((pendingNavigationIndex ?? chapterIndex) <= 0)
                .opacity((pendingNavigationIndex ?? chapterIndex) <= 0 ? 0.35 : 1.0)

                VStack(spacing: 2) {
                    if let target = pendingNavigationIndex, navigationFailureMessage == nil {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Chương \(target + 1)")
                        }
                    } else {
                        Text(totalChaptersCount > 0 ? "\(readerPresentedChapterIndex + 1)/\(totalChaptersCount)" : "0/0")
                    }
                    Text(String(format: "%.1f%%", readerProgressPercent))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(selectedTheme.textColor.opacity(0.68))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selectedTheme.textColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .allowsHitTesting(false)

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onNextChapter()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReaderNavPressButtonStyle(highlightColor: selectedTheme.textColor))
                .disabled((pendingNavigationIndex ?? chapterIndex) >= totalChaptersCount - 1)
                .opacity((pendingNavigationIndex ?? chapterIndex) >= totalChaptersCount - 1 ? 0.35 : 1.0)
            }
            .foregroundColor(selectedTheme.textColor)
            .frame(height: 52)
            .background(readerChromeBackground.ignoresSafeArea(edges: .bottom))
        }
    }

    private struct ReaderNavPressButtonStyle: ButtonStyle {
        let highlightColor: Color

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(configuration.isPressed ? highlightColor.opacity(0.12) : Color.clear)
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .opacity(configuration.isPressed ? 0.7 : 1.0)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}
