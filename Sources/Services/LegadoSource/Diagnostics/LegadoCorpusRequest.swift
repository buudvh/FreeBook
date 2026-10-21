import Foundation

/// Đầu vào đã kiểm của một lượt nghiệm thu. Chỉ nhận đúng ba thứ client được phép gửi (rules.md, debug server 1.3.303 #2):
/// danh sách `packageId` **hoặc** "mọi nguồn Legado đang bật", từ khoá tuỳ chọn, giới hạn số nguồn tuỳ chọn.
/// Không có URL, đường dẫn hay JS: từ khoá client luôn là từ khoá tìm kiếm thuần — các tiền tố gỡ lỗi `++`/`--`/URL/
/// `tên::url` chỉ được hiểu khi đọc từ `checkKeyWord` trong `source.json` của chính nguồn (spec §5.10).
struct LegadoCorpusRequest: Sendable, Equatable {
    enum Selection: Sendable, Equatable {
        case allEnabled
        case packageIds([String])

        var label: String {
            switch self {
            case .allEnabled: return "allEnabled"
            case .packageIds: return "packageIds"
            }
        }
    }

    struct Issue: Error, Sendable {
        let message: String
    }

    /// Từ khoá mặc định khi nguồn không khai `checkKeyWord` và client không gửi từ khoá (spec §5.10: giá trị hay gặp).
    static let fallbackKeyword = "我的"
    static let maxKeywordLength = 100
    static let maxPackageIds = 10_000

    let selection: Selection
    let defaultKeyword: String
    /// `nil` = không giới hạn.
    let limit: Int?

    static func make(
        packageIds: [String]?,
        allEnabled: Bool?,
        keyword: String?,
        limit: Int?
    ) -> Result<LegadoCorpusRequest, Issue> {
        let ids = uniqueTrimmed(packageIds ?? [])
        let wantsAll = allEnabled ?? false
        let selection: Selection
        if wantsAll {
            guard ids.isEmpty else {
                return .failure(Issue(message: "Chỉ gửi một trong hai: packageIds hoặc allEnabled"))
            }
            selection = .allEnabled
        } else {
            guard !ids.isEmpty else {
                return .failure(Issue(message: "Thiếu packageIds hoặc allEnabled: true"))
            }
            guard ids.count <= maxPackageIds else {
                return .failure(Issue(message: "Quá \(maxPackageIds) packageId trong một lượt"))
            }
            selection = .packageIds(ids)
        }

        let trimmedKeyword = (keyword ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKeyword.count <= maxKeywordLength else {
            return .failure(Issue(message: "Từ khoá dài quá \(maxKeywordLength) ký tự"))
        }
        if looksLikeDebugCommand(trimmedKeyword) {
            return .failure(Issue(message: "Từ khoá phải là từ khoá tìm kiếm thuần — không nhận URL hay tiền tố ++/--/::"))
        }

        if let limit, limit < 0 {
            return .failure(Issue(message: "limit phải ≥ 0 (0 = không giới hạn)"))
        }
        let effectiveLimit = (limit ?? 0) > 0 ? limit : nil

        return .success(LegadoCorpusRequest(
            selection: selection,
            defaultKeyword: trimmedKeyword.isEmpty ? fallbackKeyword : trimmedKeyword,
            limit: effectiveLimit
        ))
    }

    private static func uniqueTrimmed(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            output.append(trimmed)
        }
        return output
    }

    private static func looksLikeDebugCommand(_ keyword: String) -> Bool {
        keyword.hasPrefix("++") || keyword.hasPrefix("--") || keyword.contains("://") || keyword.contains("::")
    }
}
