import Foundation

/// Chủ dữ liệu danh sách **"Tiền tố"** của Lọc name local (plan `Docs/Plans/2026-11-27-phan-loai-name.md` L7 / L10, dùng
/// chung mọi truyện) — cùng bộ máy với danh sách "Hậu tố" (`LocalNameFilterAffixListStore`), cùng dạng dòng
/// `chữ Hán=nghĩa|loại|vị trí`, cùng kiểu mục `LocalNameFilterSuffixEntry` / `LocalNameFilter.Suffix`.
///
/// - **Bản gốc**: `NameFilterPrefixes.txt` trong bundle (`老=lão|person|before`, `小=tiểu|person|before`).
/// - **Lớp riêng**: `UserDefaults` khoá `localNameFilterPrefixOverrides` (khoá vắng = bản gốc; chữ thường ⇒ Backup tự gói).
///
/// **Chỉ để ghép nghĩa** (không dò, không đổi loại): `allPrefixes()` ⇒ `LocalNameFilter.Configuration.prefixes`. Mảnh tên mở
/// đầu bằng một tiền tố **cùng nhóm loại** (loại `person` ⇄ tên người; place / sect / term ⇄ name không phải người), phần sau
/// ≥ 2 chữ ra tên Latin ⇒ "nghĩa tiền tố + tên" theo vị trí (老尼尔 ⇒ "lão Neil") — `LocalNameFilterProperNames`. Khoá 1–6
/// chữ Hán; tiền tố mới mặc định "Trước tên".
final class LocalNameFilterPrefixStore: LocalNameFilterAffixListStore {
    static let shared = LocalNameFilterPrefixStore()

    /// Chữ thường để `BackupSettingsArchiver` tự sao lưu.
    static let userDefaultsKey = "localNameFilterPrefixOverrides"
    /// Tên file gốc trong bundle (XcodeGen làm phẳng thư mục ⇒ tên phải duy nhất trong cả app).
    static let bundledResourceName = "NameFilterPrefixes"

    private init() {
        super.init(
            defaultsKey: LocalNameFilterPrefixStore.userDefaultsKey,
            resourceName: LocalNameFilterPrefixStore.bundledResourceName,
            noun: "Tiền tố"
        )
    }

    /// Mọi tiền tố của danh sách, đúng dạng bộ lọc dùng (`LocalNameFilter.Configuration.prefixes`).
    func allPrefixes() -> [LocalNameFilter.Suffix] {
        entries().map(\.suffix)
    }
}
