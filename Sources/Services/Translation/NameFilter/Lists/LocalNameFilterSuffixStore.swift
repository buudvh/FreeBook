import Foundation

/// Chủ dữ liệu danh sách **"Hậu tố"** của Lọc name local (dùng chung mọi truyện) — bộ máy chung ở
/// `LocalNameFilterAffixListStore` (đọc bản gốc, lớp riêng, trộn, kiểm, ghi).
///
/// - **Bản gốc**: `NameFilterSuffixes.txt` trong bundle — 1.299 mục: 42 địa danh, 27 tổ chức (loại `sect`), 40 thuật ngữ
///   (loại `term`) — nghĩa Hán-Việt viết thường, đặt sau tên — và 1.190 **nhân danh** (loại `person`, danh xưng sau tên
///   người, từ Pronouns của anh Bửu — plan 2026-11-27-phan-loai-name L11 / L12).
/// - **Lớp riêng**: `UserDefaults` khoá `localNameFilterSuffixOverrides`.
///
/// **Cách A** (2026-11-27, anh Bửu: "bỏ bật tắt trong danh sách đi, giờ nó dùng để dịch nghĩa thôi"): danh sách hiệu lực
/// (`allSuffixes()`, màn "Lọc name local" chụp lúc bấm "Bắt đầu lọc") **chỉ** dùng để ghép nghĩa — đuôi địa danh / tổ chức /
/// thuật ngữ cho name không phải tên người (kể cả 观 花 区), đuôi nhân danh là danh xưng của tên người. Dò ứng viên / luật
/// lọc / phân loại dùng bộ cố định `detectionSuffixes` = bản gốc trừ dòng `|off` (路 区 观 团 关 花), không theo lớp riêng.
final class LocalNameFilterSuffixStore: LocalNameFilterAffixListStore {
    static let shared = LocalNameFilterSuffixStore()

    /// Chữ thường để `BackupSettingsArchiver` tự sao lưu.
    static let userDefaultsKey = "localNameFilterSuffixOverrides"
    /// Tên file gốc trong bundle (XcodeGen làm phẳng thư mục ⇒ tên phải duy nhất trong cả app).
    static let bundledResourceName = "NameFilterSuffixes"

    private init() {
        super.init(
            defaultsKey: LocalNameFilterSuffixStore.userDefaultsKey,
            resourceName: LocalNameFilterSuffixStore.bundledResourceName,
            noun: "Hậu tố"
        )
    }

    /// Mọi mục của danh sách, đúng dạng bộ lọc dùng (`LocalNameFilter.Configuration.suffixes` — chỉ để ghép nghĩa).
    func allSuffixes() -> [LocalNameFilter.Suffix] {
        entries().map(\.suffix)
    }

    /// Bộ đuôi **dò** cố định của bộ lọc = bản gốc trừ dòng `|off`, không theo lớp riêng (cách A). `LocalNameFilterSetup`
    /// đọc mỗi lượt lọc và tự chọn độ dài dùng được (địa danh / tổ chức / thuật ngữ 1–2 chữ, nhân danh 2–6 chữ).
    static var detectionSuffixes: [LocalNameFilter.Suffix] {
        shared.base.lines.filter(\.isDetectable).map {
            LocalNameFilter.Suffix(key: $0.key, meaning: $0.value.meaning, kind: $0.value.kind, position: $0.value.position)
        }
    }
}
