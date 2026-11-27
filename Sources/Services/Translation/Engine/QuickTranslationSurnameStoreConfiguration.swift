import Foundation

/// Cấu hình một bản `QuickTranslationSurnameStore` (L13, plan 2026-11-27-phan-loai-name — anh Bửu: "Màn quản lý họ riêng
/// cho lọc luôn"): **một** code cho hai danh sách họ độc lập, mỗi bản có file gốc + lớp riêng của mình.
///
/// - `quickTranslation`: danh sách của token `<ho>` trong rule dịch nhanh — đúng khoá / file / hành vi trước L13.
/// - `nameFilter`: danh sách riêng của Lọc name local (`LocalNameFilterDictionaries`). Sửa bên nào không đổi bên kia.
///
/// Khoá `UserDefaults` chữ thường ⇒ `BackupSettingsArchiver` tự gói. Tên file gốc phải duy nhất trong cả app (XcodeGen
/// làm phẳng thư mục resource).
struct QuickTranslationSurnameStoreConfiguration: Sendable {
    /// Chép **một lần** lớp riêng của một danh sách khác sang danh sách này lúc bản store được dùng lần đầu.
    struct Seed: Sendable {
        /// Khoá lớp riêng của danh sách nguồn.
        let sourceKey: String
        /// Cờ "đã xét chép" — đặt cả khi không có gì để chép. Chữ thường ⇒ Backup gói cùng lớp riêng, nên khôi phục bản
        /// sao lưu đã qua bước chép không chép lại đè lên danh sách vừa khôi phục.
        let markerKey: String
    }

    /// Tên file gốc trong bundle, không có `.txt`.
    let bundledResourceName: String
    /// Khoá `UserDefaults` của lớp riêng (JSON `QuickTranslationSurnameOverrides`, vắng = đúng bản gốc).
    let userDefaultsKey: String
    /// Nhãn đầu dòng log của bản này.
    let logTag: String
    /// Danh sách có đi vào bộ dịch không (`<ho>`): có ⇒ mỗi lần ghi dọn cache dịch + báo rule đổi. Danh sách của bộ lọc
    /// không đổi bản dịch nên không làm hai việc đó (như `LocalNameFilterSuffixStore`).
    let affectsTranslation: Bool
    let seed: Seed?

    static let quickTranslation = Self(
        bundledResourceName: "ChineseSurnames",
        userDefaultsKey: "quickTranslateSurnameOverrides",
        logTag: "[Surname]",
        affectsTranslation: true,
        seed: nil
    )

    /// Bản gốc `NameFilterSurnames.txt` = `ChineseSurnames.txt` + 洛 Lạc, 玉 Ngọc. Anh Bửu chọn "chép họ đã sửa": họ anh đã
    /// thêm / sửa / xoá / tắt ở Danh sách họ của `<ho>` được chép sang một lần, để kết quả lọc không tự đổi khi tách danh sách.
    static let nameFilter = Self(
        bundledResourceName: "NameFilterSurnames",
        userDefaultsKey: "localNameFilterSurnameOverrides",
        logTag: "[NameFilterSurname]",
        affectsTranslation: false,
        seed: Seed(sourceKey: quickTranslation.userDefaultsKey, markerKey: "localNameFilterSurnameSeeded")
    )
}
