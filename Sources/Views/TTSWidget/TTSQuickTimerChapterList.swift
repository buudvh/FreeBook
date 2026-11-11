import SwiftUI
import UIKit

/// Tab "Danh sách chương" của sheet Hẹn giờ TTS (`TTSQuickTimerSheet`).
///
/// - Cột số thứ tự như các mục lục khác (`ChapterOrdinalLabel`, công tắc `ChapterOrdinalNumbering.showsOrdinalKey`):
///   `chaptersQueue` là mục lục đủ theo thứ tự gốc (chỉ số = vị trí) ⇒ số = `index + 1`, giữ nguyên khi đang lọc. Bề
///   rộng cột tính một lần cho cả danh sách, không trong từng hàng.
/// - Ô tìm ẩn mặc định (vùng danh sách nhỏ ở nấc 0.88): nút kính nổi góc dưới phải (cùng kiểu nút "+" ở Kệ) mở ô và
///   bật bàn phím, mở rồi thì nút thành ✕ (xoá từ khoá + ẩn ô). Bàn phím đóng khi ô trống ⇒ ô tự ẩn.
/// - Lọc giống ô tìm mục lục Reader: `ChapterTitleSearchMatcher` trên tên đang hiển thị (bản dịch nếu phiên TTS bật
///   dịch) và tên gốc; chờ 250 ms sau phím cuối, chạy ngoài main (dịch cả mục lục), phím mới huỷ lượt cũ.
/// - Chương đang phát chỉ đổi màu nền + chữ đậm, không có chip hay icon.
struct TTSQuickTimerChapterList: View {
    @ObservedObject var ttsManager: TTSManager

    @AppStorage(ChapterOrdinalNumbering.showsOrdinalKey)
    private var showsChapterOrdinal = ChapterOrdinalNumbering.showsOrdinalDefault
    @State private var isSearchVisible = false
    @State private var searchQuery = ""
    /// `nil` = không lọc (hiện cả mục lục).
    @State private var filteredChapters: [TTSChapterInfo]? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    /// Tăng để cuộn lại tới chương đang phát (sau khi đóng ô tìm).
    @State private var scrollToPlayingRequest = 0
    @FocusState private var isSearchFocused: Bool

    private static let rowFont = Font.system(size: 14)

    var body: some View {
        VStack(spacing: 0) {
            if isSearchVisible {
                ChapterTOCSearchField(
                    text: $searchQuery,
                    placeholder: "Tìm kiếm \(ttsManager.chaptersQueue.count) chương",
                    palette: .system,
                    onSubmit: { isSearchFocused = false },
                    focus: $isSearchFocused
                )
                // Ô tự chừa 6pt bên phải (cân với nút sắp xếp của panel Mục lục) ⇒ lề phải 10 để hai bên đều 16.
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            chapterScroll
        }
        .onChange(of: searchQuery) { _, newValue in
            scheduleFilter(newValue)
        }
        .onChange(of: ttsManager.chaptersQueue.count) { _, _ in
            // Mục lục làm mới khi đang lọc ⇒ lọc lại trên bản mới.
            if filteredChapters != nil { scheduleFilter(searchQuery) }
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused && trimmedQuery.isEmpty && isSearchVisible {
                withAnimation(.easeInOut(duration: 0.2)) { isSearchVisible = false }
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chapterScroll: some View {
        let chapters = ttsManager.chaptersQueue
        let rows = filteredChapters ?? chapters
        // Bề rộng cột số theo số lớn nhất của mục lục đủ (không theo kết quả lọc) ⇒ tên không nhảy ngang khi gõ.
        let ordinalDigits = showsChapterOrdinal
            ? ChapterOrdinalNumbering(chapterCount: max(chapters.count, (chapters.last?.index ?? -1) + 1)).digits
            : 0
        let playingIndex = ttsManager.playingChapterIndex
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows, id: \.index) { chapter in
                        chapterRow(chapter, isPlaying: chapter.index == playingIndex, ordinalDigits: ordinalDigits)
                            .id(chapter.index)
                    }
                    if filteredChapters?.isEmpty == true {
                        Text("Không có chương nào khớp")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.immediately)
            .floatingAddButton(
                isSearchVisible ? "Đóng tìm chương" : "Tìm chương",
                systemImage: isSearchVisible ? "xmark" : "magnifyingglass",
                action: toggleSearch
            )
            .onAppear { scrollToPlaying(proxy) }
            .onChange(of: scrollToPlayingRequest) { _, _ in scrollToPlaying(proxy) }
        }
    }

    private func chapterRow(_ chapter: TTSChapterInfo, isPlaying: Bool, ordinalDigits: Int) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            ttsManager.jumpToChapter(at: chapter.index)
        }) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if ordinalDigits > 0 {
                    ChapterOrdinalLabel(
                        ordinal: chapter.index + 1,
                        digits: ordinalDigits,
                        palette: .system,
                        isCurrent: isPlaying,
                        isRead: false,
                        font: Self.rowFont
                    )
                    .padding(.trailing, 8)
                }
                Text(ttsManager.displayTitle(for: chapter))
                    .font(Self.rowFont.weight(isPlaying ? .bold : .regular))
                    .foregroundStyle(isPlaying ? Color.primary : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isPlaying ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isPlaying ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func scrollToPlaying(_ proxy: ScrollViewProxy) {
        let playingIndex = ttsManager.playingChapterIndex
        guard playingIndex >= 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            proxy.scrollTo(playingIndex, anchor: .center)
        }
    }

    // MARK: - Tìm chương

    private func toggleSearch() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if isSearchVisible {
            searchTask?.cancel()
            searchQuery = ""
            filteredChapters = nil
            isSearchFocused = false
            withAnimation(.easeInOut(duration: 0.2)) { isSearchVisible = false }
            scrollToPlayingRequest += 1
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { isSearchVisible = true }
            // Ô vừa được dựng ở lượt này: gán focus ở lượt main kế tiếp mới bật được bàn phím.
            DispatchQueue.main.async { isSearchFocused = true }
        }
    }

    private func scheduleFilter(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if filteredChapters != nil {
                filteredChapters = nil
                scrollToPlayingRequest += 1
            }
            return
        }
        let chapters = ttsManager.chaptersQueue
        let options = ttsManager.sessionTextOptions
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let matched = await Self.matchingChapters(
                in: chapters,
                query: trimmed,
                options: options
            )
            guard !Task.isCancelled else { return }
            filteredChapters = matched
        }
    }

    /// `nonisolated async` ⇒ chạy ngoài main; huỷ theo task gọi. Tên hiển thị chọn **y như**
    /// `TTSManager.displayTitle(for:)` (cùng `sessionTextOptions`: phồn → giản cả khi tắt dịch, dịch sống khi phiên bật
    /// dịch) — sửa một bên thì sửa cả hai.
    nonisolated private static func matchingChapters(
        in chapters: [TTSChapterInfo],
        query: String,
        options: ChineseTextPipeline.Options
    ) async -> [TTSChapterInfo] {
        var matched: [TTSChapterInfo] = []
        for (offset, chapter) in chapters.enumerated() {
            if offset % 200 == 0, Task.isCancelled { return [] }
            let raw = chapter.title
            let display = ChineseTextPipeline.chapterTitle(raw, options)
            if ChapterTitleSearchMatcher.matches(query, anyOf: [display, raw]) {
                matched.append(chapter)
            }
        }
        return matched
    }
}
