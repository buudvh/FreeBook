import Foundation
import Observation

/// Tên chương + tên truyện ở **đầu trang** và **mục lục** Reader dịch bằng **tiện ích dịch** như tên chương trong chương
/// (1.3.853). `ReaderView` giữ một store (`@State`) cho cả phiên đọc, truyền xuống sheet mục lục.
///
/// - **Tên chương** — theo **chỉ số chương**, cùng luật với `TranslationExtensionChapterTranslator.translateTitle`:
///   bộ dịch sang tiếng Việt (`Request.targetsVietnamese`) và chương có `title_trans` ⇒ dùng `title_trans`, không gọi
///   tiện ích; không thì tiện ích (`source = tableOfContent`, chữ đã chuyển phồn → giản, `cacheBookId = bookId`) ⇒ trúng
///   cùng cache RAM của runner với đường trong chương; tiện ích lỗi ⇒ `title(at:)` trả `nil` ⇒ màn hiện bản QT (chỉ
///   log, không dải báo).
/// - **Tên truyện** — `book` (`ExtensionTextTranslationStore`, `source = detail`, kiểu `meta`): một store mỗi `source`.
///
/// Chỉ xin dịch chương **đang hiện**: `title(at:)` gọi trong `body` (hàng mục lục đang dựng, tên chương đầu trang) xếp
/// chỉ số vào hàng chờ (chỉ ghi trường `@ObservationIgnored`); sau một nhịp ngắn cả nhịp đi **một** lượt — đọc tên gốc
/// (`ChapterStore` với truyện đã lưu, mục lục online với truyện chưa lưu) rồi gửi một lô. Bản dịch chỉ ở RAM; đổi cấu hình
/// dịch / phồn → giản / bộ dịch (`update`, gọi ngoài `body`) ⇒ bỏ hết, dịch lại khi hàng hiện lại.
///
/// `public` chỉ vì `ReaderChapterListView` (public) nhận nó trong `init`; mọi thành viên vẫn `internal`.
@MainActor
@Observable
public final class ReaderTitleTranslationStore {
    /// Tên truyện (`kind: .meta`).
    let book = ExtensionTextTranslationStore()

    /// Tên chương đã có theo chỉ số (bản tiện ích hoặc `title_trans`).
    private var chapterTitles: [Int: String] = [:]

    /// Quan sát được: màn đã vẽ lúc còn QT phải vẽ lại khi lượt tiện ích bật để `title(at:)` kịp xin dịch.
    private(set) var chapterRequest: ChineseTextExtensionTranslator.Request?
    @ObservationIgnored private var bookId = ""
    /// Truyện đã lưu ⇒ đọc tên gốc + `title_trans` ở `ChapterStore`; chưa lưu ⇒ `onlineTitles`.
    @ObservationIgnored private var readsStoredTOC = false
    @ObservationIgnored private var onlineTitles: [String] = []
    @ObservationIgnored private var queued = Set<Int>()
    @ObservationIgnored private var requested = Set<Int>()
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private static let flushDelay: UInt64 = 150_000_000
    /// Trần số tên giữ trong RAM; vượt ⇒ xoá hết (lượt sau lấy lại từ cache RAM của tiện ích, không gọi lại).
    private static let maxEntries = 3000
    /// Chỉ số cách nhau quá mức này ⇒ đọc `ChapterStore` thành nhiều đoạn (kết quả tìm rải rác).
    private static let maxRangeGap = 40

    init() {}

    /// Đổi cấu hình (ngoài `body`: `.task(id:)`, `.onChange`). `chapterRequest` / `bookRequest` = `nil` ⇒ bộ dịch QT
    /// hoặc tắt dịch ⇒ màn hiện bản QT. Đổi lượt dịch / nguồn tên ⇒ bỏ tên chương đã dịch.
    func update(
        bookId: String,
        options: ChineseTextPipeline.Options,
        chapterRequest: ChineseTextExtensionTranslator.Request?,
        bookRequest: ChineseTextExtensionTranslator.Request?,
        readsStoredTOC: Bool,
        onlineTitles: [String]
    ) {
        book.update(options: options, request: bookRequest)
        let sourceChanged = bookId != self.bookId || readsStoredTOC != self.readsStoredTOC
            || (!readsStoredTOC && onlineTitles != self.onlineTitles)
        self.onlineTitles = onlineTitles
        guard sourceChanged || chapterRequest != self.chapterRequest else { return }
        self.bookId = bookId
        self.readsStoredTOC = readsStoredTOC
        if chapterRequest != self.chapterRequest { self.chapterRequest = chapterRequest }
        generation &+= 1
        flushTask?.cancel()
        flushTask = nil
        queued.removeAll()
        requested.removeAll()
        if !chapterTitles.isEmpty { chapterTitles.removeAll() }
    }

    /// Tên chương `index` theo bộ dịch tiện ích (gọi được trong `body`). `nil` ⇒ dùng bản QT của màn: bộ dịch QT / tắt
    /// dịch, chưa dịch xong (đã xin), hoặc tiện ích lỗi.
    func title(at index: Int) -> String? {
        guard chapterRequest != nil, index >= 0 else { return nil }
        if let hit = chapterTitles[index] { return hit }
        enqueue(index)
        return nil
    }

    // MARK: - Nội bộ

    private func enqueue(_ index: Int) {
        guard !requested.contains(index), !queued.contains(index) else { return }
        queued.insert(index)
        guard flushTask == nil else { return }
        scheduleFlush(token: generation)
    }

    private func scheduleFlush(token: Int) {
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.flushDelay)
            await self?.flush(token: token)
        }
    }

    private func flush(token: Int) async {
        flushTask = nil
        guard token == generation, let request = chapterRequest, !queued.isEmpty else { return }
        let batch = queued.sorted()
        queued.removeAll()
        requested.formUnion(batch)

        let sources = await sourceTitles(for: batch)
        guard token == generation else { return }
        // Chưa đọc được tên gốc (truyện vừa lên kệ, `ChapterStore` chưa ghi mục lục / đọc lỗi) ⇒ xin lại ở lượt vẽ sau.
        requested.subtract(batch.filter { sources[$0] == nil })
        var resolved: [Int: String] = [:]
        var sendIndices: [Int] = []
        var sendTexts: [String] = []
        for index in batch {
            guard let source = sources[index], !source.title.isEmpty else { continue }
            if request.targetsVietnamese, let stored = source.stored { resolved[index] = stored; continue }
            sendIndices.append(index)
            sendTexts.append(source.title)
        }
        if !sendTexts.isEmpty {
            do {
                let output = try await ChineseTextExtensionTranslator.translate(sendTexts, request: request)
                for (index, text) in zip(sendIndices, output.texts) {
                    if let text, !text.isEmpty { resolved[index] = text }
                }
                if let status = output.fallbackStatus {
                    AppLogger.shared.log("❌ [ExtTranslate] Tên chương đầu trang / mục lục: \(status.failedLineCount)/\(sendTexts.count) lỗi ⇒ QT — \(status.message)")
                }
            } catch {
                // Huỷ — không phải lỗi; chương chưa dịch được xin lại ở lượt vẽ sau.
                if token == generation { requested.subtract(batch) }
                return
            }
        }
        guard token == generation else { return }
        if chapterTitles.count + resolved.count > Self.maxEntries {
            chapterTitles.removeAll()
            requested = Set(batch)
        }
        if !resolved.isEmpty { chapterTitles.merge(resolved) { _, new in new } }
        if !queued.isEmpty, flushTask == nil { scheduleFlush(token: token) }
    }

    /// Tên gốc (đã trim; rỗng vẫn trả để khỏi xin lại) + `title_trans` (nếu có) của các chương `indices`. Không có trong
    /// kết quả = chưa đọc được dòng mục lục đó.
    private func sourceTitles(for indices: [Int]) async -> [Int: (title: String, stored: String?)] {
        var result: [Int: (title: String, stored: String?)] = [:]
        guard readsStoredTOC else {
            for index in indices where index < onlineTitles.count {
                result[index] = (onlineTitles[index].trimmingCharacters(in: .whitespacesAndNewlines), nil)
            }
            return result
        }
        let wanted = Set(indices)
        for range in Self.ranges(of: indices) {
            guard let rows = try? await ChapterStore.shared.fetchRange(
                bookId: bookId, startIndex: range.lowerBound, count: range.count
            ) else { continue }
            for row in rows where wanted.contains(row.index) {
                let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let stored = row.titleTrans?.trimmingCharacters(in: .whitespacesAndNewlines)
                result[row.index] = (title, (stored?.isEmpty ?? true) ? nil : stored)
            }
        }
        return result
    }

    /// Chỉ số đã sắp xếp ⇒ các đoạn liền nhau (cách nhau ≤ `maxRangeGap`).
    private static func ranges(of sorted: [Int]) -> [ClosedRange<Int>] {
        var ranges: [ClosedRange<Int>] = []
        for index in sorted {
            if let last = ranges.last, index - last.upperBound <= maxRangeGap {
                ranges[ranges.count - 1] = last.lowerBound...index
            } else {
                ranges.append(index...index)
            }
        }
        return ranges
    }
}
