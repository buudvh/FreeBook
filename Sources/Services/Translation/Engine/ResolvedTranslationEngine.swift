import Foundation

/// Kết quả tra bộ dịch cho một truyện (`TranslationEngineStore.resolve`): lựa chọn đang hiệu lực, cấp quyết định nó, và
/// tên hiển thị. Tiện ích đã gỡ / không còn là loại `translate` ⇒ `selection` lùi về QT, `unavailablePackageId` giữ
/// mã tiện ích đó để giao diện báo được.
public struct ResolvedTranslationEngine: Equatable, Sendable {
    public enum Origin: String, Sendable {
        case book
        case source
        case global
    }

    public let selection: TranslationEngineSelection
    public let origin: Origin
    /// Tên tiện ích dịch đang dùng; `nil` với QT.
    public let extensionName: String?
    /// Tiện ích được chọn nhưng không dùng được (đã gỡ / đổi loại) ⇒ đang chạy QT thay.
    public let unavailablePackageId: String?

    public var usesExtension: Bool { selection.packageId != nil }

    /// Tên bộ dịch để hiện ở giao diện.
    public var displayName: String {
        extensionName ?? TranslationEngineStore.quickTranslatorName
    }
}
