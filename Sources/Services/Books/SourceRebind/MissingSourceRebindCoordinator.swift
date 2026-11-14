import Foundation
import Observation
import SwiftData

/// Truyện mất nguồn → tiện ích đã cài khớp link chi tiết.
///
/// - **Mất nguồn**: truyện ở Kệ hoặc Lịch sử có `extensionPackageId` không còn cài (không tính sách nhập từ file).
/// - **Ứng viên**: tiện ích đã cài trừ nguồn Legado, cùng loại nội dung khi còn tra được loại của nguồn cũ, có `regexp`
///   khớp **cả chuỗi** `detailUrl` (`ExtensionUrlMatcher.WholeMatcher`, đúng hợp đồng tiện ích).
/// - **Chuyển**: thử từng ứng viên theo thứ tự đã cài, theo kết quả `SourceRebindValidator`:
///   - cùng link chương ⇒ gắn lại nguồn tại chỗ (`BookTransactionCoordinator.rebindSource`, giữ `bookId`);
///   - link khác dạng nhưng cùng vị trí ⇒ luồng Đổi nguồn (`BookSourceChangeCoordinator.run`: truyện mới với mục lục
///     nguồn mới, chép chương đã tải theo vị trí, chép thiết lập riêng, xoá truyện cũ);
///   - lệch cả tên ⇒ bỏ qua ứng viên đó.
///   Một truyện một lúc, không chạy song song.
/// - Dò tự động chỉ ở trang gốc Kệ (`MissingSourceRebindBanner`); sheet nhấn giữ của truyện chạy tay cho một truyện.
///   Chi tiết/Reader giữ `extensionPackageId` cố định từ lúc mở và Chi tiết tìm truyện theo cặp (link, tiện ích), nên
///   không ghi khi màn đọc của truyện đang mở.
/// - Truyện thử không được nhớ trong phiên để dải báo không gọi mạng lại mỗi lần mở Kệ (chạy tay thì vẫn thử).
@MainActor
@Observable
final class MissingSourceRebindCoordinator {
    static let shared = MissingSourceRebindCoordinator()

    /// Giá trị của một truyện mất nguồn — không mang instance `Book` qua `await` (luồng Đổi nguồn còn xoá nó).
    struct Candidate: Identifiable, Equatable {
        let bookId: String
        let title: String
        let author: String
        let oldPackageId: String
        let detailUrl: String
        let host: String?
        let currentChapterIndex: Int
        let isOnShelf: Bool
        let isHistory: Bool
        let lastReadDate: Date
        /// Tiện ích khớp link, theo thứ tự đã cài.
        let packageIds: [String]

        var id: String { bookId }

        func limited(to packageId: String) -> Candidate {
            Candidate(bookId: bookId, title: title, author: author, oldPackageId: oldPackageId, detailUrl: detailUrl,
                      host: host, currentChapterIndex: currentChapterIndex, isOnShelf: isOnShelf, isHistory: isHistory,
                      lastReadDate: lastReadDate, packageIds: [packageId])
        }
    }

    struct Report {
        /// `newBookId == oldBookId` khi gắn lại tại chỗ; khác khi đi luồng Đổi nguồn (View chuyển phiên AI theo cặp này).
        var switched: [(oldBookId: String, newBookId: String, title: String, extName: String)] = []
        /// Đi luồng Đổi nguồn mà chép chương đã tải lỗi ⇒ giữ lại truyện cũ.
        var keptOldBooks = 0
        var incompatible = 0
        var failed = 0
    }

    private enum Outcome {
        case rebound(extName: String)
        case changed(newBookId: String, extName: String, keptOldBook: Bool)
        case incompatible
        case failed
        /// Truyện đã được đổi nguồn ở chỗ khác trong lúc kiểm mục lục.
        case skipped
        /// Đã rời trang gốc Kệ hoặc truyện đang mở: dừng lượt, lần hiện Kệ sau thử lại.
        case deferred
    }

    private(set) var isRunning = false
    private(set) var statusText = ""
    /// Người dùng ẩn dải báo trong phiên này.
    var isBannerDismissed = false
    /// Trang gốc Kệ đang hiện (`MissingSourceRebindBanner` đặt ở `onAppear`/`onDisappear`). Mỗi truyện tốn vài giây
    /// kiểm mục lục, người dùng có thể đã rời Kệ và mở chính truyện đó ⇒ lượt của dải báo chỉ ghi khi Kệ còn hiện.
    @ObservationIgnored var isShelfRootVisible = false

    @ObservationIgnored private var attemptedBookIds: Set<String> = []
    @ObservationIgnored private var isBookOpen: (String) -> Bool = { _ in false }
    @ObservationIgnored private var requiresShelfRoot = true

    private init() {}

    /// Chỉ đọc RAM (bảng tiện ích đã cài + cache `regexp`), không gọi mạng: gọi được mỗi lần trang Kệ hiện.
    /// `includingAttempted`: sheet nhấn giữ (chạy tay) vẫn hiện truyện đã thử không được trong phiên.
    func candidates(from books: [Book], includingAttempted: Bool = false) -> [Candidate] {
        let missing = books.filter {
            ($0.isOnShelf || $0.isHistory) && (includingAttempted || !attemptedBookIds.contains($0.bookId))
                && Self.isMissingSource($0.extensionPackageId)
        }
        guard !missing.isEmpty else { return [] }
        let pool = ExtensionUrlMatcher.candidates(from: ExtensionLibraryRepository.shared.installed)
            .filter { SearchExtensionScopePolicy.isBrowsable($0) }
        guard !pool.isEmpty else { return [] }

        var matchers: [ExtensionContentKind?: ExtensionUrlMatcher.WholeMatcher] = [:]
        var seen = Set<String>()
        var result: [Candidate] = []
        for book in missing where seen.insert(book.bookId).inserted {
            let kind = ExtensionContentKind.resolveIfKnown(packageId: book.extensionPackageId)
            let matcher: ExtensionUrlMatcher.WholeMatcher
            if let cached = matchers[kind] {
                matcher = cached
            } else {
                let scoped = kind.map { bookKind in pool.filter { SearchExtensionScopePolicy.kind(of: $0) == bookKind } } ?? pool
                matcher = ExtensionUrlMatcher.WholeMatcher(extensions: scoped)
                matchers[kind] = matcher
            }
            let packageIds = matcher.matches(for: book.detailUrl).map(\.ext.packageId)
            guard !packageIds.isEmpty else { continue }
            result.append(Candidate(
                bookId: book.bookId,
                title: book.title,
                author: book.author,
                oldPackageId: book.extensionPackageId,
                detailUrl: book.detailUrl,
                host: book.host,
                currentChapterIndex: book.currentChapterIndex,
                isOnShelf: book.isOnShelf,
                isHistory: book.isHistory,
                lastReadDate: book.lastReadDate,
                packageIds: packageIds
            ))
        }
        return result
    }

    /// Tiện ích nguồn không còn cài. Sách nhập từ file (`local`, truyện tranh/phim nhập) không có tiện ích nguồn.
    static func isMissingSource(_ packageId: String) -> Bool {
        let trimmed = packageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "local", !LocalMediaPackage.isLocalMedia(packageId: trimmed) else {
            return false
        }
        return ExtensionLibraryRepository.snapshot(packageId: trimmed) == nil
    }

    /// Chạy lần lượt từng truyện. Đang có lượt Đổi nguồn (hay lượt gắn lại khác) thì không làm gì.
    /// - `isBookOpen`: truyện đang mở ở màn đọc (View truyền vào — tầng Service không tra `ReaderView`).
    /// - `requiresShelfRoot`: lượt của dải báo dừng khi rời trang gốc Kệ; chạy tay từ sheet nhấn giữ (Kệ, Tìm trên kệ,
    ///   Bộ sưu tập — đều là danh sách, không màn nào của truyện đang mở) thì không cần.
    func run(
        _ candidates: [Candidate],
        isInteractive: Bool,
        requiresShelfRoot: Bool,
        context: ModelContext,
        isBookOpen: @escaping (String) -> Bool
    ) async -> Report {
        var report = Report()
        guard !isRunning, !BookSourceChangeCoordinator.shared.isRunning, !candidates.isEmpty else { return report }
        isRunning = true
        self.isBookOpen = isBookOpen
        self.requiresShelfRoot = requiresShelfRoot
        defer {
            isRunning = false
            statusText = ""
            self.isBookOpen = { _ in false }
            self.requiresShelfRoot = true
        }
        loop: for (offset, candidate) in candidates.enumerated() {
            guard canWrite(candidate.bookId) else { break }
            statusText = "Đang chuyển nguồn \(offset + 1)/\(candidates.count)..."
            switch await rebind(candidate, isInteractive: isInteractive, context: context) {
            case .rebound(let extName):
                report.switched.append((oldBookId: candidate.bookId, newBookId: candidate.bookId, title: candidate.title, extName: extName))
            case .changed(let newBookId, let extName, let keptOldBook):
                report.switched.append((oldBookId: candidate.bookId, newBookId: newBookId, title: candidate.title, extName: extName))
                if keptOldBook { report.keptOldBooks += 1 }
            case .incompatible:
                report.incompatible += 1
            case .failed:
                report.failed += 1
            case .skipped:
                break
            case .deferred:
                AppLogger.shared.log("[SourceRebind] Rời Kệ hoặc mở truyện giữa lượt, dừng ở \(offset + 1)/\(candidates.count)")
                break loop
            }
        }
        return report
    }

    private func canWrite(_ bookId: String) -> Bool {
        (!requiresShelfRoot || isShelfRootVisible) && !isBookOpen(bookId)
    }

    private func rebind(_ candidate: Candidate, isInteractive: Bool, context: ModelContext) async -> Outcome {
        var sawError = false
        for packageId in candidate.packageIds {
            guard let ext = ExtensionLibraryRepository.snapshot(packageId: packageId) else { continue }
            do {
                let verdict = try await SourceRebindValidator.check(
                    bookId: candidate.bookId,
                    title: candidate.title,
                    detailUrl: candidate.detailUrl,
                    currentChapterIndex: candidate.currentChapterIndex,
                    oldHost: candidate.host,
                    ext: ext,
                    isInteractive: isInteractive
                )
                switch verdict.match {
                case .different:
                    AppLogger.shared.log("❌ [SourceRebind] \(candidate.bookId) → \(ext.packageId): mục lục khác cả link lẫn tên chương, không chuyển — \(verdict.mismatchSummary)")
                    continue
                case .samePositions:
                    guard canWrite(candidate.bookId) else { return .deferred }
                    AppLogger.shared.log("[SourceRebind] \(candidate.bookId) → \(ext.packageId): link chương khác dạng, chuyển bằng luồng Đổi nguồn — \(verdict.mismatchSummary)")
                    let outcome = try await changeSource(candidate, ext: ext, bookHost: verdict.bookHost, context: context)
                    // Truyện cũ được giữ (đang nghe TTS, chép chương lỗi) vẫn mất nguồn ⇒ không để dải báo chạy lại mỗi lần mở Kệ.
                    if outcome.keptOldBook { attemptedBookIds.insert(candidate.bookId) }
                    return .changed(newBookId: outcome.newBookId, extName: ext.name, keptOldBook: outcome.keptOldBook)
                case .sameLinks:
                    guard canWrite(candidate.bookId) else { return .deferred }
                    switch rebindInPlace(candidate, ext: ext, bookHost: verdict.bookHost, context: context) {
                    case .success(true):
                        AppLogger.shared.log("[SourceRebind] \(candidate.bookId): \(candidate.oldPackageId) → \(ext.packageId)")
                        return .rebound(extName: ext.name)
                    case .success(false):
                        return .skipped
                    case .failure(let error):
                        AppLogger.shared.log("❌ [SourceRebind] Không ghi được nguồn mới cho \(candidate.bookId): \(error.localizedDescription)")
                        sawError = true
                    }
                }
            } catch {
                AppLogger.shared.log("❌ [SourceRebind] \(candidate.bookId) → \(ext.packageId) lỗi: \(error.localizedDescription)")
                sawError = true
            }
        }
        attemptedBookIds.insert(candidate.bookId)
        return sawError ? .failed : .incompatible
    }

    private func rebindInPlace(_ candidate: Candidate, ext: Extension, bookHost: String, context: ModelContext) -> Result<Bool, Error> {
        BookTransactionCoordinator.shared.rebindSource(
            bookId: candidate.bookId,
            expectedOldPackageId: candidate.oldPackageId,
            packageId: ext.packageId,
            sourceName: ext.name,
            sourceUrl: ext.sourceUrl,
            host: bookHost,
            in: context
        )
    }

    /// Như "Đổi nguồn" của màn Tìm kiếm (`SearchView+SourceChange`), với kết quả tìm dựng từ chính link chi tiết cũ.
    /// Đang nghe TTS truyện đó ⇒ giữ truyện cũ để không ngắt quãng nghe.
    private func changeSource(
        _ candidate: Candidate,
        ext: Extension,
        bookHost: String,
        context: ModelContext
    ) async throws -> BookSourceChangeCoordinator.Outcome {
        try BookSourceMigrator.ensureSameContentKind(oldPackageId: candidate.oldPackageId, newPackageId: ext.packageId)
        // Lượt Đổi nguồn trước còn dọn truyện cũ (~1,2 s sau mốc chốt) ⇒ chờ, nếu không `run` báo `.busy`.
        var waited = 0
        while BookSourceChangeCoordinator.shared.isRunning, waited < 40 {
            try await Task.sleep(nanoseconds: 250_000_000)
            waited += 1
        }
        let request = BookSourceChangeCoordinator.Request(
            oldBookId: candidate.bookId,
            oldTitle: candidate.title,
            oldChapterIndex: candidate.currentChapterIndex,
            oldIsOnShelf: candidate.isOnShelf,
            oldIsHistory: candidate.isHistory,
            oldLastReadDate: candidate.lastReadDate,
            result: ExtensionItemResult(name: candidate.title, author: candidate.author, link: candidate.detailUrl, host: bookHost),
            ext: ext
        )
        let total = statusText
        return try await BookSourceChangeCoordinator.shared.run(request, container: context.container) { [weak self] status in
            self?.statusText = total.isEmpty ? status : "\(total) \(status)"
        }
    }
}
