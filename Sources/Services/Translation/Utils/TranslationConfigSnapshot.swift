import Foundation

/// Bản chụp cấu hình **dịch** + **phồn → giản** của `TranslationConfigStore` (1.3.846): đọc các từ điển `UserDefaults`
/// một lần rồi tra bao nhiêu truyện / nguồn cũng được, không khoá lock hay đọc lại `UserDefaults` mỗi lần.
///
/// Là **nguồn duy nhất** của luật phân cấp: `TranslationConfigStore.resolveStatus` và
/// `convertsTraditionalToSimplified` chỉ chụp rồi gọi vào đây. Danh sách dài (Kệ, Khám phá, Tìm kiếm) chụp một lần mỗi
/// lượt dựng rồi truyền vào `ChineseTextPipeline.options(…, in:)`.
///
/// - Dịch: Truyện ⇒ Nguồn ⇒ gợi ý "nguồn tiếng Trung" ⇒ dò nguồn (`isChineseSource`) ⇒ Tất cả (chỉ khi không có nguồn
///   hoặc sách nhập từ file).
/// - Phồn → giản: Truyện ⇒ Nguồn ⇒ Tất cả.
/// - `bookId` rỗng / `nil` bỏ qua cấp truyện; `packageId` `nil` bỏ qua cấp nguồn, rỗng = `"local"` (như store).
public struct TranslationConfigSnapshot: Sendable {
    typealias ScopeOverride = TranslationConfigStore.ScopeOverride

    let globalEnabled: Bool
    let globalConvertsTraditional: Bool
    let bookOverrides: [String: Int]
    let sourceOverrides: [String: Int]
    let sourceTraditional: [String: Bool]

    // MARK: - Dịch

    public func resolveStatus(
        bookId: String?,
        packageId: String?,
        isChineseSourceHint: Bool? = nil
    ) -> TranslationConfigStore.ResolvedStatus {
        let store = TranslationConfigStore.shared
        let bOverride = bookOverride(bookId)
        let sOverride = sourceOverride(packageId)

        func status(_ isEnabled: Bool, _ origin: TranslationConfigStore.ResolvedOrigin) -> TranslationConfigStore.ResolvedStatus {
            TranslationConfigStore.ResolvedStatus(
                isEnabled: isEnabled, origin: origin, bookOverride: bOverride, sourceOverride: sOverride,
                globalEnabled: globalEnabled
            )
        }

        if bOverride != .inherited { return status(bOverride == .enabled, .book) }
        if sOverride != .inherited { return status(sOverride == .enabled, .source) }

        if let hint = isChineseSourceHint, let pkgId = packageId, !pkgId.isEmpty {
            store.registerSource(packageId: pkgId, isChinese: hint)
            return status(hint, .source)
        }

        if let pkgId = packageId, !pkgId.isEmpty, !TranslationConfigStore.isLocalPackage(pkgId) {
            return status(store.isChineseSource(packageId: pkgId), .source)
        }

        return status(globalEnabled, .global)
    }

    public func isTranslationEnabled(bookId: String?, packageId: String?, isChineseSourceHint: Bool? = nil) -> Bool {
        resolveStatus(bookId: bookId, packageId: packageId, isChineseSourceHint: isChineseSourceHint).isEnabled
    }

    // MARK: - Phồn → giản

    public func convertsTraditional(bookId: String?, packageId: String?) -> Bool {
        if let bookId, !bookId.isEmpty {
            let key = TranslationConfigStore.bookTraditionalKey(bookId)
            if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.bool(forKey: key) }
        }
        if let packageId, let value = sourceTraditional[Self.normalizedPackageId(packageId)] {
            return value
        }
        return globalConvertsTraditional
    }

    // MARK: - Tra từng cấp

    func bookOverride(_ bookId: String?) -> ScopeOverride {
        guard let bookId, !bookId.isEmpty,
              let raw = bookOverrides[bookId], let mode = ScopeOverride(rawValue: raw) else { return .inherited }
        return mode
    }

    func sourceOverride(_ packageId: String?) -> ScopeOverride {
        guard let packageId,
              let raw = sourceOverrides[Self.normalizedPackageId(packageId)],
              let mode = ScopeOverride(rawValue: raw) else { return .inherited }
        return mode
    }

    static func normalizedPackageId(_ packageId: String) -> String {
        packageId.isEmpty ? "local" : packageId
    }
}
