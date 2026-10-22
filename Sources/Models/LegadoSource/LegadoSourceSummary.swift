import Foundation

/// Bản tóm tắt **bất biến** của một nguồn Legado đã lưu — đủ cho danh sách ở tab "Nguồn Legado" và cho tầng nền
/// kiểm tra nhanh (bật/tắt, loại) mà không phải đọc lại `source.json`.
///
/// Tên/nhóm gốc giữ nguyên; `translatedName`/`translatedGroups` là bản dịch QT do `LegadoSourceRepository` gắn
/// (rỗng / bằng bản gốc khi chưa dịch xong hoặc từ điển chưa nạp). Tên nguồn **hiển thị bản gốc** (`displayName`);
/// tên dịch chỉ dùng cho ô tìm. Nhóm vẫn hiển thị bản dịch.
public struct LegadoSourceSummary: Sendable, Identifiable, Hashable {
    public let packageId: String
    public let name: String
    public internal(set) var translatedName: String
    public let groups: [String]
    /// Cùng thứ tự, cùng số phần tử với `groups`.
    public internal(set) var translatedGroups: [String]
    public let kind: LegadoSourceKind
    public internal(set) var isEnabled: Bool
    public let enabledExplore: Bool
    public let needsLogin: Bool
    /// Nguyên văn (khoá định danh, spec §1.4).
    public let bookSourceUrl: String
    public let hasSearchRules: Bool
    public let hasExploreRules: Bool
    /// `version` trong bản ghi kho tiện ích (= `metadata.version` của `plugin.json`).
    public let version: Int
    /// Chuỗi đã gấp hoa thường + bỏ dấu của tên gốc, tên dịch và URL — ô tìm so trên chuỗi này.
    public internal(set) var searchKey: String
    /// Khoá sắp xếp: tên hiển thị đã gấp.
    public internal(set) var sortKey: String

    public var id: String { packageId }

    /// Tên hiển thị: **tên gốc** của nguồn — người dùng yêu cầu không dịch tên nguồn ở Kho Tiện Ích (2026-10-22).
    /// `translatedName` vẫn được giữ để ô tìm khớp cả khi gõ tên đã dịch.
    public var displayName: String { name }

    public var isUngrouped: Bool { groups.isEmpty }

    public init(packageId: String, source: LegadoBookSource, version: Int) {
        self.packageId = packageId
        name = source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        translatedName = ""
        groups = source.groups
        translatedGroups = source.groups
        kind = source.kind
        isEnabled = source.enabled
        enabledExplore = source.enabledExplore
        needsLogin = source.needsLogin
        bookSourceUrl = source.bookSourceUrl
        hasSearchRules = source.hasSearchRules
        hasExploreRules = source.hasExploreRules
        self.version = version
        searchKey = ""
        sortKey = ""
        refreshDerivedKeys()
    }

    /// Gắn bản dịch từ bảng `gốc → dịch`; chuỗi chưa có trong bảng giữ bản gốc.
    mutating func applyTranslations(_ memo: [String: String]) {
        translatedName = memo[name] ?? name
        translatedGroups = groups.map { memo[$0] ?? $0 }
        refreshDerivedKeys()
    }

    /// Gấp chuỗi cho tìm kiếm/sắp xếp: chữ thường, bỏ dấu (gõ "tieu thuyet" vẫn khớp "Tiểu thuyết"), `đ` → `d`.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
    }

    private mutating func refreshDerivedKeys() {
        searchKey = Self.fold(name + "\n" + translatedName + "\n" + bookSourceUrl)
        sortKey = Self.fold(displayName)
    }
}
