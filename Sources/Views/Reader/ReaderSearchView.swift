import SwiftUI

/// Sheet "Tìm trong chương": tìm trên các chương **đã nạp sẵn trong RAM** của Reader (chương đang
/// đọc + vài chương lân cận đã cache). Khớp cả chữ gốc lẫn chữ đã dịch qua `ReaderSearchMatcher`;
/// bấm một kết quả sẽ nhảy tới đúng đoạn qua closure `onSelect`.
///
/// `onSelect` trả kèm **từ khoá đã trim** để `ReaderView` tô lại đúng chữ đó trên trang; sheet
/// không tự tính `NSRange` vì range phải tính trên chuỗi đang hiển thị ở trang đọc.
///
/// View chỉ nhận **snapshot bất biến** các chương (dựng sẵn từ `ReaderViewModel.cache` ở `ReaderView`),
/// nên nó không giữ tham chiếu tới view model và không kích hoạt nạp chương mới.
struct ReaderSearchView: View {
    let chapters: [ReaderSearchMatcher.Chapter]
    let chapterTitles: [Int: String]
    let currentChapterIndex: Int
    let onSelect: (_ chapterIndex: Int, _ paragraphIndex: Int, _ query: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var hits: [ReaderSearchMatcher.Hit] = []
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var isSearchFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nhóm kết quả theo chương, giữ thứ tự chương tăng dần.
    private var groupedHits: [(chapterIndex: Int, hits: [ReaderSearchMatcher.Hit])] {
        let grouped = Dictionary(grouping: hits, by: { $0.chapterIndex })
        return grouped.keys.sorted().map { key in
            (chapterIndex: key, hits: grouped[key] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                content
            }
            .navigationTitle("Tìm trong chương")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .onAppear { isSearchFocused = true }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: - Thanh tìm kiếm

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Tìm chữ gốc hoặc chữ đã dịch…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .focused($isSearchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                    hits = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Nội dung

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            emptyState(
                icon: "text.magnifyingglass",
                title: "Tìm trong các chương đang mở",
                message: "Chỉ tìm chương đang đọc và các chương lân cận đã tải, khớp cả chữ gốc và chữ đã dịch."
            )
        } else if hits.isEmpty {
            emptyState(
                icon: "magnifyingglass",
                title: "Không có kết quả",
                message: "Không thấy \"\(trimmedQuery)\" trong các chương hiện đang mở."
            )
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            ForEach(groupedHits, id: \.chapterIndex) { group in
                Section {
                    ForEach(group.hits) { hit in
                        Button {
                            onSelect(hit.chapterIndex, hit.paragraphIndex, trimmedQuery)
                            dismiss()
                        } label: {
                            resultRow(hit)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    sectionHeader(for: group.chapterIndex, count: group.hits.count)
                }
            }
        }
        .listStyle(.plain)
    }

    private func resultRow(_ hit: ReaderSearchMatcher.Hit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if hit.isTitle {
                    tag("Tiêu đề", color: .orange)
                }
                tag(hit.matchedInTranslated ? "Bản dịch" : "Gốc",
                    color: hit.matchedInTranslated ? .blue : .secondary)
                Spacer(minLength: 0)
            }
            Text(highlightedSnippet(hit.snippet))
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func sectionHeader(for chapterIndex: Int, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(chapterDisplayTitle(chapterIndex))
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            if chapterIndex == currentChapterIndex {
                tag("Đang đọc", color: .green)
            }
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Trợ giúp

    private func chapterDisplayTitle(_ index: Int) -> String {
        if let title = chapterTitles[index], !title.isEmpty {
            return title
        }
        return "Chương \(index + 1)"
    }

    /// Tô đậm phần khớp trong đoạn trích (không phân biệt dấu/hoa thường).
    private func highlightedSnippet(_ snippet: String) -> AttributedString {
        var attributed = AttributedString(snippet)
        let needle = trimmedQuery
        guard !needle.isEmpty else { return attributed }
        if let range = snippet.range(of: needle, options: [.diacriticInsensitive, .caseInsensitive], range: nil, locale: .current),
           let attributedRange = Range(range, in: attributed) {
            attributed[attributedRange].font = .subheadline.weight(.bold)
            attributed[attributedRange].foregroundColor = .accentColor
        }
        return attributed
    }

    /// Debounce ~250ms rồi tìm; huỷ lần tìm trước nếu người dùng gõ tiếp.
    private func scheduleSearch() {
        searchTask?.cancel()
        let currentQuery = query
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let results = ReaderSearchMatcher.search(query: currentQuery, in: chapters)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.hits = results
            }
        }
    }
}
