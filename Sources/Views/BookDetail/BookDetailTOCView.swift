import SwiftUI

struct BookDetailTOCView: View {
    @Binding var chapterSearchQuery: String
    let totalChaps: Int
    @Binding var isTocAscending: Bool
    let tocErrorMessage: String
    let isLoadingTOC: Bool
    let localBook: Book?
    let filteredLocalChapters: [Chapter]
    let filteredOnlineChapters: [(offset: Int, element: ChapterResult)]
    let tocPages: [String]
    let remainingPagesLoaded: Bool

    let onLoadTOCDataOnly: () -> Void
    let onStartReading: (Int) -> Void
    let onTranslateChapterTitleIfNeeded: (Chapter) -> String
    let onTranslateTitleIfNeeded: (String) -> String
    let onLoadMoreChapters: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBarView
            tocListView
        }
    }

    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Tìm kiếm chương...", text: $chapterSearchQuery)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.none)
            if !chapterSearchQuery.isEmpty {
                Button(action: { chapterSearchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var tocListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Danh sách chương (\(totalChaps))")
                        .font(.headline)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTocAscending.toggle()
                        }
                    }) {
                        Image(systemName: isTocAscending ? "arrow.down.circle" : "arrow.up.circle")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                    .padding(.leading, 4)

                    Spacer()
                    if totalChaps > 0 && !tocErrorMessage.isEmpty {
                        Button(action: onLoadTOCDataOnly) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("Tải lại lỗi")
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)

                if isLoadingTOC && totalChaps == 0 {
                    HStack {
                        Spacer()
                        ProgressView("Đang tải danh sách chương...")
                            .padding(.vertical, 30)
                        Spacer()
                    }
                } else if totalChaps == 0 {
                    if !tocErrorMessage.isEmpty {
                        VStack(spacing: 12) {
                            Text(tocErrorMessage)
                                .foregroundColor(.red)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button("Tải lại mục lục") {
                                onLoadTOCDataOnly()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Không tìm thấy chương nào hoặc lỗi tải chương")
                            .foregroundColor(.gray)
                            .padding()
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let book = localBook {
                            ForEach(filteredLocalChapters) { chap in
                                Button(action: {
                                    onStartReading(chap.index)
                                }) {
                                    HStack {
                                        Text(onTranslateChapterTitleIfNeeded(chap))
                                            .foregroundColor(book.currentChapterIndex == chap.index ? .accentColor : .primary)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Spacer()
                                        if chap.isCached {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal)
                                    Divider()
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            ForEach(filteredOnlineChapters, id: \.offset) { index, chap in
                                Button(action: {
                                    onStartReading(index)
                                }) {
                                    VStack(alignment: .leading) {
                                        Text(onTranslateTitleIfNeeded(chap.name))
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .padding(.vertical, 12)
                                            .padding(.horizontal)
                                        Divider()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if tocPages.count > 1 && !remainingPagesLoaded {
                            Button(action: onLoadMoreChapters) {
                                HStack {
                                    Spacer()
                                    Text("Tải thêm chương (còn \(tocPages.count - 1) trang)")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                                .padding(.horizontal)
                                .padding(.top, 10)
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }
}
