import Foundation

/// Bộ dịch được chọn ở một cấp (Truyện / Nguồn / Toàn cục): QT có sẵn (`packageId == nil`) hoặc một tiện ích loại
/// `translate`, kèm cặp ngôn ngữ nguồn → đích của tiện ích đó.
///
/// Ngôn ngữ đi theo cấp (hợp đồng tiện ích: truyện ⇒ nguồn ⇒ toàn cục), còn model / kiểu dịch là cài đặt riêng của
/// từng tiện ích (`TranslationExtensionSettingsStore`). QT luôn dịch Trung → Việt nên `from`/`to` của nó bỏ qua.
public struct TranslationEngineSelection: Codable, Hashable, Sendable {
    /// `nil` = QT (VietPhrase) có sẵn.
    public var packageId: String?
    /// Mã ngôn ngữ nguồn theo `language.js` của tiện ích; `""` = tự nhận (chỉ khi tiện ích khai `support_auto_detect`).
    public var from: String
    /// Mã ngôn ngữ đích theo `language.js`.
    public var to: String

    public init(packageId: String?, from: String = "zh", to: String = "vi") {
        let trimmed = packageId?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.packageId = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.from = from
        self.to = to
    }

    public static let quickTranslator = TranslationEngineSelection(packageId: nil)

    public var isQuickTranslator: Bool { packageId == nil }
}
