import Foundation
import Observation
import SwiftData

/// Truyện mất nguồn → tiện ích đã cài khớp link chi tiết.
///
/// - **Mất nguồn**: truyện ở Kệ hoặc Lịch sử có `extensionPackageId` không còn cài (không tính sách nhập từ file).
/// - **Ứng viên**: tiện ích đã cài trừ nguồn Legado, cùng loại nội dung khi còn tra được loại của nguồn cũ, có `regexp`
///   khớp **cả chuỗi** `detailUrl` (`ExtensionUrlMatcher.WholeMatcher`, đúng hợp đồng tiện ích).
/// - **Chuyển**: thử từng ứng viên theo thứ tự đã cài; ứng viên đầu tiên qua `SourceRebindValidator` thì gắn lại nguồn
///   tại chỗ (`BookTransactionCoordinator.rebindSource`, giữ `bookId`). Một truyện một lúc, không chạy song song.
/// - Chỉ dò khi trang gốc Kệ hiện (`MissingSourceRebindBanner`): Chi tiết/Reader giữ `extensionPackageId` cố định từ
///   lúc mở, và Chi tiết tìm truyện theo cặp (link, tiện ích), nên gắn lại nguồn khi màn của truyện đang mở là màn đó
///   mất truyện. Ở trang gốc Kệ thì không màn nào của Kệ đang mở.
/// - Truyện thử không được (mục lục khác dạng, lỗi tải) nhớ trong phiên để không gọi mạng lại mỗi lần mở Kệ.
@MainActor
@Observable
final class MissingSourceRebindCoordinator {
    static let shared = MissingSourceRebindCoordinator()

    /// Giá trị của một truyện mất nguồn — không mang instance `Book` qua `await`.
    struct Candidate: Identifiable, Equatable {
        let bookId: String
        let title: String
        let oldPackageId: String
        let detailUrl: String
        let host: String?
        let currentChapterIndex: Int
        /// Tiện ích khớp link, theo thứ tự đã cài.
        let packageIds: [String]

        var id: String { bookId }
    }

    struct Report {
        var rebound: [(bookId: String, title: String, extName: String)] = []
        var incompatible = 0
        var failed = 0
    }

    private enum Outcome {
        case rebound(extName: String)
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
    /// kiểm mục lục, người dùng có thể đã rời Kệ và mở chính truyện đó ⇒ chỉ ghi khi Kệ còn hiện.
    @ObservationIgnored var isShelfRootVisible = false

    @ObservationIgnored private var attemptedBookIds: Set<String> = []
    @ObservationIgnored private var isBookOpen: (String) -> Bool = { _ in false }

    private init() {}

    /// Chỉ đọc RAM (bảng tiện ích đã cài + cache `regexp`), không gọi mạng: gọi được mỗi lần trang Kệ hiện.
    func candidates(from books: [Book]) -> [Candidate] {
        let missing = books.filter {
            ($0.isOnShelf || $0.isHistory) && !attemptedBookIds.contains($0.bookId) && Self.isMissingSource($0.extensionPackageId)
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
                oldPackageId: book.extensionPackageId,
                detailUrl: book.detailUrl,
                host: book.host,
                currentChapterIndex: book.currentChapterIndex,
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

    /// Chạy lần lượt từng truyện. Đang có lượt Đổi nguồn (hay lượt gắn lại khác) thì không làm gì. `isBookOpen`: truyện
    /// đang mở ở màn đọc (View truyền vào — tầng Service không tra `ReaderView`).
    func run(
        _ candidates: [Candidate],
        isInteractive: Bool,
        context: ModelContext,
        isBookOpen: @escaping (String) -> Bool
    ) async -> Report {
        var report = Report()
        guard !isRunning, !BookSourceChangeCoordinator.shared.isRunning, !candidates.isEmpty else { return report }
        isRunning = true
        self.isBookOpen = isBookOpen
        defer {
            isRunning = false
            statusText = ""
            self.isBookOpen = { _ in false }
        }
        loop: for (offset, candidate) in candidates.enumerated() {
            guard canWrite(candidate.bookId) else { break }
            statusText = "Đang chuyển nguồn \(offset + 1)/\(candidates.count)..."
            switch await rebind(candidate, isInteractive: isInteractive, context: context) {
            case .rebound(let extName):
                report.rebound.append((bookId: candidate.bookId, title: candidate.title, extName: extName))
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
        isShelfRootVisible && !isBookOpen(bookId)
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
                guard verdict.isCompatible else {
                    AppLogger.shared.log("[SourceRebind] \(candidate.bookId): mục lục \(ext.packageId) khác dạng link chương, bỏ qua")
                    continue
                }
                guard canWrite(candidate.bookId) else { return .deferred }
                let result = BookTransactionCoordinator.shared.rebindSource(
                    bookId: candidate.bookId,
                    expectedOldPackageId: candidate.oldPackageId,
                    packageId: ext.packageId,
                    sourceName: ext.name,
                    sourceUrl: ext.sourceUrl,
                    host: verdict.bookHost,
                    in: context
                )
                switch result {
                case .success(true):
                    AppLogger.shared.log("[SourceRebind] \(candidate.bookId): \(candidate.oldPackageId) → \(ext.packageId)")
                    return .rebound(extName: ext.name)
                case .success(false):
                    return .skipped
                case .failure(let error):
                    AppLogger.shared.log("❌ [SourceRebind] Không ghi được nguồn mới cho \(candidate.bookId): \(error.localizedDescription)")
                    sawError = true
                }
            } catch {
                AppLogger.shared.log("❌ [SourceRebind] Kiểm \(ext.packageId) cho \(candidate.bookId) lỗi: \(error.localizedDescription)")
                sawError = true
            }
        }
        attemptedBookIds.insert(candidate.bookId)
        return sawError ? .failed : .incompatible
    }
}
