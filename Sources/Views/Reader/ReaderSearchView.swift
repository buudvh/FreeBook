import SwiftUI

/// Sheet "Tìm trong chương": tìm trên chương đang đọc + các chương liền kề đã dựng trong RAM của Reader, rồi **nạp thêm ở
/// hai đầu** (1.3.980, anh Bửu: "load vô hạn 2 đầu, đầu trên sẽ tìm tiếp trang trước, đầu dưới sẽ load trang sau"):
/// kéo tới đầu trên ⇒ tìm thêm chương liền trước, đầu dưới ⇒ chương liền sau — **mỗi lần đúng một chương**; chương chưa
/// tải về máy thì tải từ nguồn rồi tìm (`ReaderViewModel.loadChapterForSearch`). Hàng ở hai đầu cũng bấm được (khi chương
/// vừa tìm không có kết quả, hàng vẫn nằm trên màn ⇒ bấm để tìm tiếp). Khớp cả chữ gốc lẫn chữ đã dịch
/// (`ReaderSearchMatcher`); bấm một kết quả sẽ nhảy tới đúng đoạn qua `onSelect`.
///
/// - Trạng thái (chương đã nạp, dãy đã tìm, trạng thái hai đầu) ở `ReaderSearchSession`; view chỉ vẽ.
/// - `ScrollView` + `LazyVStack` (không `List`) với `scrollPosition(id:)`: chèn chương lên **đầu** danh sách vẫn giữ nguyên
///   chỗ đang xem (bài học 1.3.822 — `List` nhảy vị trí khi nối thêm). Mở sheet thì cuộn tới chương đang đọc.
/// - `onSelect` trả kèm **từ khoá đã trim** để `ReaderView` tô lại đúng chữ đó trên trang; sheet không tự tính `NSRange` vì
///   range phải tính trên chuỗi đang hiển thị ở trang đọc.
struct ReaderSearchView: View {
    /// Truy vấn lần trước trong lượt đọc này — mở lại sheet thì điền sẵn và tìm ngay.
    var initialQuery: String
    /// Báo truy vấn cuối khi sheet đóng để `ReaderView` giữ cho lần mở sau. Không nối thẳng `Binding` vào `@State` của
    /// `ReaderView`: mỗi phím gõ sẽ bắt cả thân Reader vẽ lại.
    var onQueryChange: (String) -> Void
    let onSelect: (_ chapterIndex: Int, _ paragraphIndex: Int, _ query: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var session: ReaderSearchSession
    @State private var query: String = ""
    /// Hàng đang ở mép trên vùng cuộn — `scrollPosition` giữ nó đứng yên khi chèn chương lên đầu.
    @State private var scrollAnchor: String?
    @FocusState private var isSearchFocused: Bool

    init(
        initialChapters: [ReaderSearchMatcher.Chapter],
        initialTitles: [Int: String],
        currentChapterIndex: Int,
        totalChapters: Int,
        initialQuery: String = "",
        onQueryChange: @escaping (String) -> Void = { _ in },
        chapterTitle: @escaping @MainActor (Int) -> String,
        loadChapter: @escaping @MainActor (Int) async throws -> ReaderSearchMatcher.LoadedChapter,
        onSelect: @escaping (_ chapterIndex: Int, _ paragraphIndex: Int, _ query: String) -> Void
    ) {
        self.initialQuery = initialQuery
        self.onQueryChange = onQueryChange
        self.onSelect = onSelect
        _session = State(initialValue: ReaderSearchSession(
            initialChapters: initialChapters,
            initialTitles: initialTitles,
            currentChapterIndex: currentChapterIndex,
            totalChapters: totalChapters,
            fallbackTitle: chapterTitle,
            loader: loadChapter
        ))
        _scrollAnchor = State(initialValue: Row.chapter(currentChapterIndex).id)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                content
            }
            .pageTitle("Tìm trong chương")
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            isSearchFocused = true
            // Gán qua `onChange` bên dưới ⇒ tìm lại ngay trên các chương đang có.
            if query.isEmpty, !initialQuery.isEmpty {
                query = initialQuery
            }
        }
        .onChange(of: query) { _, newValue in session.setQuery(newValue) }
        .onDisappear {
            session.cancelAll()
            onQueryChange(query)
        }
    }

    // MARK: - Thanh tìm kiếm

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Tìm chữ gốc hoặc chữ đã dịch…", text: $query)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($isSearchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
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

    /// Một hàng của danh sách cuộn: hai đầu nạp thêm và một khối mỗi chương đã tìm. `id` kiểu `String` khớp `scrollAnchor`.
    private enum Row: Identifiable {
        case edge(ReaderSearchSession.Edge)
        case chapter(Int)

        var id: String {
            switch self {
            case .edge(.top): return "edge-top"
            case .edge(.bottom): return "edge-bottom"
            case .chapter(let index): return "chapter-\(index)"
            }
        }
    }

    private var rows: [Row] {
        [.edge(.top)] + session.chapterIndices.map(Row.chapter) + [.edge(.bottom)]
    }

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            emptyState(
                icon: "text.magnifyingglass",
                title: "Tìm trong chương",
                message: "Tìm chương đang đọc và các chương liền kề đã mở, khớp cả chữ gốc và chữ đã dịch. Kéo tới đầu trên / dưới danh sách để tìm thêm chương trước / sau — chương chưa tải sẽ được tải từ nguồn."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .edge(let edge):
                            edgeRow(edge)
                        case .chapter(let index):
                            chapterBlock(index, hits: session.hitsByChapter[index] ?? [])
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollAnchor, anchor: .top)
        }
    }

    private func chapterBlock(_ index: Int, hits: [ReaderSearchMatcher.Hit]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(for: index, count: hits.count)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)
            if hits.isEmpty {
                Text(session.query == trimmedQuery ? "Không có kết quả trong chương này" : "Đang tìm…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            } else {
                ForEach(hits) { hit in
                    Button {
                        onSelect(hit.chapterIndex, hit.paragraphIndex, trimmedQuery)
                        dismiss()
                    } label: {
                        resultRow(hit)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }

    /// Hàng ở hai đầu: hiện ra ⇒ nạp **một** chương (`onAppear` gắn trên khung ngoài, không đổi danh tính theo trạng thái ⇒
    /// không tự nạp liên tục khi hàng còn nằm trên màn); bấm được để tìm tiếp / thử lại.
    private func edgeRow(_ edge: ReaderSearchSession.Edge) -> some View {
        edgeContent(edge)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onAppear { session.loadMore(edge) }
    }

    @ViewBuilder
    private func edgeContent(_ edge: ReaderSearchSession.Edge) -> some View {
        if let next = session.nextIndex(edge) {
            let title = session.title(for: next)
            switch session.state(edge) {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Đang tìm \(title)…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            case .failed(let message):
                Button { session.loadMore(edge) } label: {
                    VStack(spacing: 4) {
                        Text("Không tải được \(title)")
                            .font(.footnote.weight(.semibold))
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Text("Bấm để thử lại")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.accentColor)
                    }
                    .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
            case .idle:
                Button { session.loadMore(edge) } label: {
                    Label(
                        "\(edge == .top ? "Tìm chương trước" : "Tìm chương sau") · \(title)",
                        systemImage: edge == .top ? "arrow.up.circle" : "arrow.down.circle"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        } else {
            Text(edge == .top ? "Đầu truyện" : "Hết truyện")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func resultRow(_ hit: ReaderSearchMatcher.Hit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if hit.isTitle {
                    tag("Tiêu đề", color: .orange)
                }
                tag(hit.matchedInTranslated ? "Bản dịch" : "Gốc",
                    color: hit.matchedInTranslated ? .white : .secondary)
                Spacer(minLength: 0)
            }
            Text(highlightedSnippet(hit.snippet))
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func sectionHeader(for chapterIndex: Int, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(session.title(for: chapterIndex))
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            if chapterIndex == session.currentChapterIndex {
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

    /// Tô đậm phần khớp trong đoạn trích (không phân biệt dấu/hoa thường).
    private func highlightedSnippet(_ snippet: String) -> AttributedString {
        var attributed = AttributedString(snippet)
        let needle = trimmedQuery
        guard !needle.isEmpty else { return attributed }
        if let range = snippet.range(of: needle, options: [.diacriticInsensitive, .caseInsensitive], range: nil, locale: .current),
           let attributedRange = Range(range, in: attributed) {
            attributed[attributedRange].font = .subheadline.weight(.bold)
            attributed[attributedRange].foregroundColor = .white
        }
        return attributed
    }
}
