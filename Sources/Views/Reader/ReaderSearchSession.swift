import Foundation
import Observation

/// Trạng thái của sheet "Tìm trong chương" (1.3.980, anh Bửu: "load vô hạn 2 đầu, đầu trên sẽ tìm tiếp trang trước, đầu dưới
/// sẽ load trang sau"; mỗi lần kéo tới một đầu tìm **đúng 1 chương**; chương chưa tải ⇒ tải từ nguồn rồi tìm).
///
/// - Các chương đã tìm luôn là một **dãy liền** `lower...upper` quanh chương đang đọc. Mở sheet: dãy = chương đang đọc + các
///   chương liền kề đã dựng sẵn trong RAM của Reader (không tải gì). Rỗng (`lower > upper`) khi chương đang đọc chưa dựng xong.
/// - `loadMore(.top)` nạp chương `lower - 1`, `loadMore(.bottom)` nạp `upper + 1` — mỗi lần một chương, mỗi đầu một lượt tải
///   tại một thời điểm; hai đầu chạy độc lập. Nạp qua `loader` (`ReaderViewModel.loadChapterForSearch`).
/// - Chương đã nạp giữ trong suốt phiên sheet; đổi từ khoá chỉ khớp lại (ngoài main, chờ 250 ms), không nạp lại.
/// - Chương nạp xong mà một lượt khớp lại đang chạy ⇒ lượt đó tự khớp thêm chương mới khi xong (`rematch`).
@MainActor
@Observable
final class ReaderSearchSession {
    enum Edge: Sendable {
        case top
        case bottom
    }

    enum EdgeState: Equatable {
        case idle
        case loading
        case failed(String)
    }

    private(set) var chapters: [Int: ReaderSearchMatcher.Chapter] = [:]
    private(set) var titles: [Int: String] = [:]
    /// Chương đầu / cuối của dãy đã tìm; `lower > upper` = chưa có chương nào.
    private(set) var lower: Int
    private(set) var upper: Int
    private(set) var hits: [ReaderSearchMatcher.Hit] = []
    private(set) var topState: EdgeState = .idle
    private(set) var bottomState: EdgeState = .idle
    /// Từ khoá (đã trim) mà `hits` đang ứng với.
    private(set) var query = ""

    let currentChapterIndex: Int
    let totalChapters: Int

    private let loader: @MainActor (Int) async throws -> ReaderSearchMatcher.LoadedChapter
    private let fallbackTitle: @MainActor (Int) -> String
    @ObservationIgnored private var matchTask: Task<Void, Never>?
    @ObservationIgnored private var edgeTasks: [Edge: Task<Void, Never>] = [:]

    init(
        initialChapters: [ReaderSearchMatcher.Chapter],
        initialTitles: [Int: String],
        currentChapterIndex: Int,
        totalChapters: Int,
        fallbackTitle: @escaping @MainActor (Int) -> String,
        loader: @escaping @MainActor (Int) async throws -> ReaderSearchMatcher.LoadedChapter
    ) {
        self.currentChapterIndex = currentChapterIndex
        self.totalChapters = totalChapters
        self.fallbackTitle = fallbackTitle
        self.loader = loader
        let byIndex = Dictionary(initialChapters.map { ($0.chapterIndex, $0) }, uniquingKeysWith: { first, _ in first })
        var low = currentChapterIndex
        var high = currentChapterIndex - 1
        if byIndex[currentChapterIndex] != nil {
            high = currentChapterIndex
            while byIndex[low - 1] != nil { low -= 1 }
            while byIndex[high + 1] != nil { high += 1 }
        }
        lower = low
        upper = high
        if low <= high {
            for index in low...high {
                chapters[index] = byIndex[index]
                titles[index] = initialTitles[index]
            }
        }
    }

    var chapterIndices: [Int] {
        lower <= upper ? Array(lower...upper) : []
    }

    var hitsByChapter: [Int: [ReaderSearchMatcher.Hit]] {
        Dictionary(grouping: hits, by: \.chapterIndex)
    }

    func title(for index: Int) -> String {
        if let title = titles[index], !title.isEmpty { return title }
        let fallback = fallbackTitle(index)
        return fallback.isEmpty ? "Chương \(index + 1)" : fallback
    }

    /// Chương kế sẽ nạp ở đầu `edge`; `nil` = đã tới đầu / cuối truyện.
    func nextIndex(_ edge: Edge) -> Int? {
        let index = edge == .top ? lower - 1 : upper + 1
        return index >= 0 && index < totalChapters ? index : nil
    }

    func state(_ edge: Edge) -> EdgeState {
        edge == .top ? topState : bottomState
    }

    // MARK: - Từ khoá

    func setQuery(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        matchTask?.cancel()
        matchTask = nil
        guard !trimmed.isEmpty else {
            query = ""
            hits = []
            return
        }
        matchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.rematch(trimmed)
        }
    }

    /// Khớp lại mọi chương đã nạp; chương nào nạp xong trong lúc khớp thì khớp thêm rồi mới gán.
    private func rematch(_ trimmed: String) async {
        var matched: Set<Int> = []
        var result: [ReaderSearchMatcher.Hit] = []
        while true {
            let pending = chapters.values.filter { !matched.contains($0.chapterIndex) }
            guard !pending.isEmpty else { break }
            let found = await Task.detached(priority: .userInitiated) {
                ReaderSearchMatcher.search(query: trimmed, in: pending)
            }.value
            guard !Task.isCancelled else { return }
            matched.formUnion(pending.map(\.chapterIndex))
            result.append(contentsOf: found)
        }
        query = trimmed
        hits = Self.sorted(result)
        matchTask = nil
    }

    // MARK: - Nạp thêm ở hai đầu

    /// Nạp **một** chương ở đầu `edge`. Bỏ qua khi chưa có từ khoá, đầu đó đang tải, hoặc đã hết chương.
    func loadMore(_ edge: Edge) {
        guard !query.isEmpty || matchTask != nil, state(edge) != .loading, let index = nextIndex(edge) else { return }
        setState(.loading, for: edge)
        edgeTasks[edge] = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await self.loader(index)
                guard !Task.isCancelled else { return }
                self.append(loaded, at: edge)
                self.setState(.idle, for: edge)
            } catch is CancellationError {
                self.setState(.idle, for: edge)
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.shared.log("❌ [ReaderSearch] Không nạp được chương \(index + 1) để tìm: \(error.localizedDescription)")
                self.setState(.failed(error.localizedDescription), for: edge)
            }
            self.edgeTasks[edge] = nil
        }
    }

    func cancelAll() {
        matchTask?.cancel()
        matchTask = nil
        edgeTasks.values.forEach { $0.cancel() }
        edgeTasks.removeAll()
    }

    private func append(_ loaded: ReaderSearchMatcher.LoadedChapter, at edge: Edge) {
        let index = loaded.chapter.chapterIndex
        // Chỉ nhận đúng chương liền kề — dãy đã tìm luôn liền.
        guard index == (edge == .top ? lower - 1 : upper + 1) else { return }
        chapters[index] = loaded.chapter
        titles[index] = loaded.title
        if lower > upper {
            lower = index
            upper = index
        } else if edge == .top {
            lower = index
        } else {
            upper = index
        }
        // Lượt khớp lại đang chạy sẽ tự khớp chương này (`rematch`); không thì khớp riêng chương mới (nhanh, trên main).
        guard matchTask == nil, !query.isEmpty else { return }
        let found = ReaderSearchMatcher.search(query: query, in: [loaded.chapter])
        if !found.isEmpty {
            hits = Self.sorted(hits + found)
        }
    }

    private func setState(_ state: EdgeState, for edge: Edge) {
        switch edge {
        case .top: topState = state
        case .bottom: bottomState = state
        }
    }

    private static func sorted(_ hits: [ReaderSearchMatcher.Hit]) -> [ReaderSearchMatcher.Hit] {
        hits.sorted { ($0.chapterIndex, $0.paragraphIndex) < ($1.chapterIndex, $1.paragraphIndex) }
    }
}
