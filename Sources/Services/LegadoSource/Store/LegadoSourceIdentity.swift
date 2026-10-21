import Foundation

/// Danh tính của nguồn Legado trong kho tiện ích.
///
/// - `packageId = "legado_" + 16 ký tự hex thường đầu của SHA-256(bookSourceUrl đã trim)` — **đóng băng**: `bookId`
///   của sách chứa `packageId`, đổi công thức là mất liên kết sách ↔ nguồn. Mọi nơi cần `packageId` từ
///   `bookSourceUrl` phải gọi `packageId(forSourceUrl:)`, không tự tính lại.
/// - Nhận diện nguồn Legado theo **`Extension.type`** thuộc họ `legado*`, **không** theo tiền tố `packageId`:
///   tiện ích JS tên "Legado X" cũng ra `packageId` `legado_x` (`ExtensionSyncCommandBuilder`).
public enum LegadoSourceIdentity {
    public static let packageIdPrefix = "legado_"
    /// `Extension.installOrigin` của bản ghi nguồn Legado (nhập từ tệp / URL / bộ nhớ tạm).
    public static let installOrigin = "legadoImport"
    /// `metadata.author` của `plugin.json` sinh tự động.
    public static let author = "Legado"
    /// `metadata.locale` ⇒ `Extension.isChineseSource` bật dịch mặc định.
    public static let locale = "zh_CN"

    /// Khoá so trùng: `bookSourceUrl` đã trim (spec §1.4 khuyến nghị lưu nguyên văn, so sau khi trim).
    public static func normalizedSourceKey(_ bookSourceUrl: String) -> String {
        bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func packageId(forSourceUrl bookSourceUrl: String) -> String {
        let digest = normalizedSourceKey(bookSourceUrl).sha256()
        return packageIdPrefix + String(digest.prefix(16))
    }

    /// `legado`, `legado_comic`, `legado_video` (và mọi `legado_*` về sau). So chính xác chữ thường — app tự ghi giá trị này.
    public static func isLegado(type: String) -> Bool {
        type == LegadoSourceKind.textExtensionType || type.hasPrefix(LegadoSourceKind.textExtensionType + "_")
    }

    public static func isLegado(_ ext: Extension) -> Bool {
        isLegado(type: ext.type)
    }

    /// Loại của bản ghi Legado; `nil` khi không phải Legado (hoặc là `legado_*` chưa biết).
    public static func kind(of ext: Extension) -> LegadoSourceKind? {
        LegadoSourceKind(extensionType: ext.type)
    }
}
