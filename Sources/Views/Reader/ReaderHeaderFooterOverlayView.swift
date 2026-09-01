import SwiftUI

struct ReaderHeaderFooterOverlayView: View {
    let selectedTheme: ReaderTheme
    @Binding var isTranslationEnabled: Bool
    @Binding var isAutoScrollDisabled: Bool
    @Binding var showChapterTitle: Bool
    @Binding var removeDuplicatedTitle: Bool
    @Binding var showingBookDictionary: Bool
    @Binding var showingBypassBrowser: Bool
    @Binding var showingSettings: Bool
    @Binding var showingChapterList: Bool
    @Binding var showingTOCRules: Bool
    @Binding var showingJunkFilter: Bool
    let readerBookDisplayTitle: String
    let readerChapterDisplayTitle: String
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
    let onToggleChapterTitle: () -> Void
    let onToggleRemoveDuplicatedTitle: () -> Void
    let onOpenChapterList: () -> Void
    let onOpenReaderSearch: () -> Void
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void
    let onOpenAppSettings: () -> Void

    var readerChromeBackground: Color {
        selectedTheme.backgroundColor
    }

    var body: some View {
        VStack {
            // Header View
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(selectedTheme.textColor)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Quay lại")

                    Spacer()

                    // Tìm trong chương — để cạnh nút cuộn theo TTS thay vì nằm trong menu "..."
                    Button(action: onOpenReaderSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(selectedTheme.textColor)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Tìm trong chương")

                    // Nút toggle tự động cuộn theo Highlight TTS - luôn hiển thị
                    Button(action: { isAutoScrollDisabled.toggle() }) {
                        Image(systemName: isAutoScrollDisabled ? "scroll" : "scroll.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isAutoScrollDisabled ? selectedTheme.textColor.opacity(0.85) : .blue)
                            .frame(width: 44, height: 44)
                            .background(selectedTheme.textColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .accessibilityLabel(isAutoScrollDisabled ? "Bật cuộn theo Highlight TTS" : "Tắt cuộn theo Highlight TTS")

                    if !isLocalTXTBook {
                        Button(action: onReloadChapter) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(selectedTheme.textColor)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Tải lại chương")
                    }

                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(selectedTheme.textColor)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Cài đặt trình đọc")

                    Menu {
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

                        Button(action: { showingTOCRules = true }) {
                            Label("Quy tắc mục lục (TOC)", systemImage: "list.bullet.indent")
                        }

                        Button(action: onOpenAppSettings) {
                            Label("Mở Cài đặt", systemImage: "gearshape.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(selectedTheme.textColor)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Tùy chọn trình đọc")
                }

                HStack(alignment: .center, spacing: 8) {
                    Button(action: { isTranslationEnabled.toggle() }) {
                        Image(systemName: isTranslationEnabled ? "character.bubble.fill" : "character.bubble")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(isTranslationEnabled ? .blue : selectedTheme.textColor.opacity(0.85))
                            .frame(width: 44, height: 52)
                            .background(selectedTheme.textColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .accessibilityLabel(isTranslationEnabled ? "Tắt dịch" : "Bật dịch")

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
            HStack(spacing: 8) {
                Button(action: onPrevChapter) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .disabled((pendingNavigationIndex ?? chapterIndex) <= 0)

                VStack(spacing: 2) {
                    if let target = pendingNavigationIndex, navigationFailureMessage == nil {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Đang tải chương \(target + 1)")
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
                .frame(maxWidth: .infinity)

                Button(action: onNextChapter) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .disabled((pendingNavigationIndex ?? chapterIndex) >= totalChaptersCount - 1)
            }
            .foregroundColor(selectedTheme.textColor)
            .frame(height: 52)
            .padding(.horizontal, 12)
            .background(readerChromeBackground.ignoresSafeArea(edges: .bottom))
        }
    }
}
