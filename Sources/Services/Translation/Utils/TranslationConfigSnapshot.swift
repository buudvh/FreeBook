import Foundation

/// Bản chụp cấu hình dịch 3 cấp (công tắc toàn cục + bảng override theo truyện + bảng override theo nguồn) để phân giải
/// cờ dịch cho **cả một danh sách** mà không đọc lại `UserDefaults` ở mỗi dòng. Thứ tự phân giải là của
/// `TranslationConfigStore.resolve` (Truyện > Nguồn > Toàn cục), không chép lại ở đây.
///
/// Bản chụp **không** tự cập nhật: view giữ nó phải chụp lại khi `TranslationConfigStore.didChangeNotification` đến, và
/// khi công tắc toàn cục đổi (công tắc đó ghi thẳng `UserDefaults` qua `@AppStorage`, không phát thông báo).
public struct TranslationConfigSnapshot: Equatable, Sendable {
    public typealias ScopeOverride = TranslationConfigStore.ScopeOverride

    public let globalEnabled: Bool
    fileprivate let bookOverrides: [String: ScopeOverride]
    fileprivate let sourceOverrides: [String: ScopeOverride]

    /// Bản rỗng (toàn cục tắt, không override) — giá trị khởi tạo của `@State` trước khi chụp thật.
    public init() {
        self.globalEnabled = false
        self.bookOverrides = [:]
        self.sourceOverrides = [:]
    }

    private init(
        globalEnabled: Bool,
        bookOverrides: [String: ScopeOverride],
        sourceOverrides: [String: ScopeOverride]
    ) {
        self.globalEnabled = globalEnabled
        self.bookOverrides = bookOverrides
        self.sourceOverrides = sourceOverrides
    }

    /// Đọc cấu hình hiện tại (ba lần đọc `UserDefaults`). Gọi một lần mỗi lượt vẽ danh sách, không gọi mỗi dòng.
    public static func current() -> TranslationConfigSnapshot {
        let store = TranslationConfigStore.shared
        return TranslationConfigSnapshot(
            globalEnabled: store.globalEnabled,
            bookOverrides: store.allBookOverrides,
            sourceOverrides: store.allSourceOverrides
        )
    }

    /// Cờ dịch của một truyện đã lưu (`Book`, tác vụ tải…): khoá override cấp truyện là `bookId`.
    /// `isChineseSourceHint == nil` ⇒ lấy từ bảng tiện ích đã cài (`installedChineseHint`).
    public func isTranslationEnabled(bookId: String?, packageId: String?, isChineseSourceHint: Bool? = nil) -> Bool {
        let bookOverride = bookId.flatMap { bookOverrides[$0] } ?? .inherited
        // Cùng quy ước với `TranslationConfigStore.getSourceOverride`: `packageId` rỗng là nguồn `local`.
        let sourceOverride = packageId.flatMap { sourceOverrides[$0.isEmpty ? "local" : $0] } ?? .inherited
        return TranslationConfigStore.shared.resolve(
            global: globalEnabled,
            bookOverride: bookOverride,
            sourceOverride: sourceOverride,
            packageId: packageId,
            isChineseSourceHint: isChineseSourceHint ?? Self.installedChineseHint(packageId)
        ).isEnabled
    }

    /// Cờ dịch cho các item của **một nguồn** chưa chắc đã thành `Book` (Khám phá, "Xem thêm", explore, Tìm kiếm).
    public func source(packageId: String, sourceName: String, isChineseSourceHint: Bool? = nil) -> Source {
        Source(config: self, packageId: packageId, sourceName: sourceName, isChineseSourceHint: isChineseSourceHint)
    }

    /// Hint "nguồn tiếng Trung" từ bảng tiện ích đã cài, để `TranslationConfigStore` khỏi đọc `plugin.json` trên đĩa.
    /// Chưa cài ⇒ `nil` (store tự tra như cũ). `local`/rỗng không bao giờ có hint: có hint thì hint thắng công tắc toàn cục.
    static func installedChineseHint(_ packageId: String?) -> Bool? {
        guard let packageId, !packageId.isEmpty, packageId != "local" else { return nil }
        return ExtensionLibraryRepository.snapshot(packageId: packageId)?.isChineseSource
    }

    /// Cờ dịch của các item thuộc **một nguồn**: cờ cấp nguồn tính một lần lúc tạo; override cấp truyện (Truyện thắng
    /// Nguồn) tra theo các `bookId` mà truyện đã lưu có thể mang — xem `candidateBookIds`.
    public struct Source: Equatable, Sendable {
        public let packageId: String
        /// Cờ cấp nguồn — cho chuỗi không thuộc truyện nào (tiêu đề màn, thể loại, tiêu đề section).
        public let isSourceEnabled: Bool
        private let sourceName: String
        private let bookOverrides: [String: ScopeOverride]

        fileprivate init(config: TranslationConfigSnapshot, packageId: String, sourceName: String, isChineseSourceHint: Bool?) {
            self.packageId = packageId
            self.isSourceEnabled = config.isTranslationEnabled(
                bookId: nil,
                packageId: packageId,
                isChineseSourceHint: isChineseSourceHint
            )
            self.sourceName = sourceName.lowercased()
            self.bookOverrides = config.bookOverrides
        }

        /// `link` = URL chi tiết của item. Truyện được đặt "Luôn bật/Luôn tắt" thắng cờ nguồn; không có override nào
        /// (trường hợp thường gặp) thì trả cờ nguồn ngay, không băm `bookId`.
        public func isTranslationEnabled(itemLink link: String) -> Bool {
            guard !bookOverrides.isEmpty, !link.isEmpty else { return isSourceEnabled }
            for candidate in candidateBookIds(link: link) {
                if let mode = bookOverrides[candidate], mode != .inherited {
                    return mode == .enabled
                }
            }
            return isSourceEnabled
        }

        /// Các `bookId` mà truyện đã lưu từ `link` này có thể mang: `BookIdUtils.make` (nhập từ trình duyệt, đổi nguồn),
        /// `"<tên nguồn>_<link>"` (mở chi tiết từ Khám phá/Tìm kiếm) và `link` trần (mở từ "Xem thêm"). Truyện được
        /// `BookDetailView.resolveBookId` gán UUID thì không suy ra được từ `link` — rơi về cờ nguồn.
        private func candidateBookIds(link: String) -> [String] {
            var ids = [BookIdUtils.make(extensionPackageId: packageId, detailUrl: link)]
            if !sourceName.isEmpty { ids.append("\(sourceName)_\(link)") }
            ids.append(link)
            return ids
        }
    }
}
