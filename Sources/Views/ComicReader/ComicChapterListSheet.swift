import SwiftUI

/// Mục lục của màn đọc comic: chương đang đọc được đánh dấu, chương đã tải offline có icon; chạm để nhảy chương.
@MainActor
struct ComicChapterListSheet: View {
    let chapters: [ComicChapterEntry]
    let currentIndex: Int
    let downloadedIndexes: Set<Int>
    let isTranslationEnabled: Bool
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    ContentUnavailableView(
                        "Chưa có mục lục",
                        systemImage: "list.bullet",
                        description: Text("Mở trang chi tiết truyện để tải mục lục.")
                    )
                } else {
                    chapterList
                }
            }
            .navigationTitle("Mục lục (\(chapters.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 38)
                    }
                    .accessibilityLabel("Đóng")
                }
            }
        }
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            List(chapters, id: \.index) { chapter in
                row(for: chapter)
                    .id(chapter.index)
            }
            .listStyle(.plain)
            .onAppear {
                // Đợi List dựng xong rồi mới cuộn tới chương đang đọc.
                DispatchQueue.main.async {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }

    private func row(for chapter: ComicChapterEntry) -> some View {
        let isCurrent = chapter.index == currentIndex
        return Button {
            onSelect(chapter.index)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text(chapter.displayTitle(translated: isTranslationEnabled))
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if downloadedIndexes.contains(chapter.index) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.green)
                        .accessibilityLabel("Đã tải offline")
                }
                if isCurrent {
                    Image(systemName: "book.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Đang đọc")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}
