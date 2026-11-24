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
/// - `List` (ô tái dùng) chứ không `ScrollView` + `LazyVStack` (1.3.1053, anh Bửu: mở mục lục từ sheet nghe mini hơi đơ
///   khi truyện nhiều chương): cuộn tới chương đang phát lúc mở, `LazyVStack` phải dựng + đo **mọi** hàng phía trước
///   (mỗi hàng còn dịch tên chương) trên main — đang nghe chương 2000 là 2000 hàng một lượt; `List` nhảy bằng chiều cao
///   ước lượng như mục lục Reader. Không observe `TTSManager` (`TTSChapterListReader` do sheet giữ).
struct TTSQuickTimerChapterList: View {
    /// Danh sách chương + chương đang phát của phiên — không theo nhịp đọc từng câu.
    @ObservedObject var reader: TTSChapterListReader

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
    /// Hai thẻ cách nhau 8 (4 + 4) như `LazyVStack(spacing: 8)` cũ; lề ngang 16.
    private static let rowInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    /// Tên màn cho dòng `🐢 [MainHang]` (`MainThreadHangMonitor.noteScreen`).
    private static let hangScreenName = "mục lục TTS mini"

    var body: some View {
        VStack(spacing: 0) {
            if isSearchVisible {
                ChapterTOCSearchField(
                    text: $searchQuery,
                    placeholder: "Tìm kiếm \(reader.chapters.count) chương",
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
            chapterList
        }
        .onChange(of: searchQuery) { _, newValue in
            scheduleFilter(newValue)
        }
        .onChange(of: reader.chapters.count) { _, _ in
            // Mục lục làm mới khi đang lọc ⇒ lọc lại trên bản mới.
            if filteredChapters != nil { scheduleFilter(searchQuery) }
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused && trimmedQuery.isEmpty && isSearchVisible {
                withAnimation(.easeInOut(duration: 0.2)) { isSearchVisible = false }
            }
        }
        .onAppear {
            // Bối cảnh cho log đo main kẹt (khuôn mục lục Reader): dòng `🐢 [MainHang]` ghi kèm tên màn này khi đang mở.
            MainThreadHangMonitor.shared.noteScreen(Self.hangScreenName, visible: true)
            AppLogger.shared.log("📑 [TTSTOC] Mở mục lục sheet nghe (\(reader.chapters.count) chương, đang nghe chương \(reader.playingChapterIndex + 1))")
        }
        .onDisappear {
            searchTask?.cancel()
            MainThreadHangMonitor.shared.noteScreen(Self.hangScreenName, visible: false)
            AppLogger.shared.log("📑 [TTSTOC] Đóng mục lục sheet nghe")
        }
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chapterList: some View {
        let chapters = reader.chapters
        let rows = filteredChapters ?? chapters
        // Bề rộng cột số theo số lớn nhất của mục lục đủ (không theo kết quả lọc) ⇒ tên không nhảy ngang khi gõ.
        let ordinalDigits = showsChapterOrdinal
            ? ChapterOrdinalNumbering(chapterCount: max(chapters.count, (chapters.last?.index ?? -1) + 1)).digits
            : 0
        let playingIndex = reader.playingChapterIndex
        // Tên chương đi qua từ điển / rule / cấu hình dịch ⇒ đọc mốc này để vẽ lại khi chúng đổi (trước đây nhịp đọc của
        // `TTSManager` vẽ lại hộ).
        _ = TranslationDisplayRevision.shared.value
        return ScrollViewReader { proxy in
            List {
                ForEach(rows, id: \.index) { chapter in
                    chapterRow(chapter, isPlaying: chapter.index == playingIndex, ordinalDigits: ordinalDigits)
                        .id(chapter.index)
                        .listRowInsets(Self.rowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if filteredChapters?.isEmpty == true {
                    Text("Không có chương nào khớp")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .listRowInsets(Self.rowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            // Nằm trong sheet kính: nền trong suốt, hàng tự vẽ thẻ. Lề trên / dưới 4 + 4 của hàng = 8 như bản cũ.
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 4, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 0)
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
            TTSManager.shared.jumpToChapter(at: chapter.index)
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
                Text(TTSManager.shared.displayTitle(for: chapter))
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
        let playingIndex = reader.playingChapterIndex
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
        let chapters = reader.chapters
        let options = TTSManager.shared.sessionTextOptions
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
