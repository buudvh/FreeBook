import Foundation

/// Phẫu thuật thuần văn bản trên **file tắt rule**: mỗi dòng là một **mẫu** (phần trước dấu `=` của
/// dòng rule), không có vế phải.
///
/// Vì sao khoá là mẫu chứ không phải số dòng: `sourceLine` đổi sau mỗi lần thêm/xoá rule, còn mẫu là
/// thứ `QuickTranslationRuleRecordStore` dùng làm khoá. Một
/// nguồn khoá duy nhất cho cả phân hệ.
///
/// Cùng tinh thần `QuickTranslationRuleRecordStore`: ở đây **không** chạm `FileManager`. Chủ file là
/// `QuickTranslationRuleDisableStore`.
public enum QuickTranslationRuleDisableFile {
    public static let header = """
    # FreeBook — danh sách rule dịch đang TẮT.
    # Mỗi dòng là một mẫu (phần trước dấu = của dòng rule). File này không chứa nội dung rule.
    # Xoá một dòng ở đây là bật lại rule đó.
    """

    /// Text → danh sách mẫu, giữ thứ tự xuất hiện và bỏ trùng.
    ///
    /// Bỏ dòng trống và dòng mở đầu `#` / `//` / `===` — đúng bộ tiền tố comment mà
    /// `QuickTranslationRuleParser` đang bỏ, để hai file cùng một quy ước comment.
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var patterns: [String] = []

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for rawLine in normalized.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("//"),
                  !trimmed.hasPrefix("===") else { continue }
            let pattern = unquote(trimmed)
            guard !pattern.isEmpty, seen.insert(pattern).inserted else { continue }
            patterns.append(pattern)
        }

        return patterns
    }

    /// Danh sách mẫu → text đầy đủ (header + từng mẫu một dòng).
    public static func serialize(_ patterns: [String]) -> String {
        guard !patterns.isEmpty else { return header + "\n" }
        return header + "\n" + patterns.joined(separator: "\n") + "\n"
    }

    /// Thêm mẫu nếu chưa có; đã có thì trả nguyên danh sách (không nhân đôi).
    public static func adding(_ pattern: String, to patterns: [String]) -> [String] {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !patterns.contains(key) else { return patterns }
        return patterns + [key]
    }

    /// Xoá **mọi** dòng bằng đúng mẫu này.
    public static func removing(_ pattern: String, from patterns: [String]) -> [String] {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return patterns }
        return patterns.filter { $0 != key }
    }

    /// Hợp tập hai danh sách, giữ thứ tự bản đang có trước — dùng cho chiều khôi phục backup
    /// ("khôi phục chỉ thêm, không xoá").
    public static func union(current: [String], imported: [String]) -> [String] {
        var result = current
        var seen = Set(current)
        for pattern in imported where seen.insert(pattern).inserted {
            result.append(pattern)
        }
        return result
    }

    /// Preview cho nhập danh sách tắt: `(added, overlapping, machineOnly)`.
    /// `added` = mẫu chưa tắt → sẽ tắt thêm; `overlapping` = mẫu đã tắt sẵn; `machineOnly` = mẫu đang tắt nhưng file không có (liên quan khi Thay thế hoàn toàn).
    public static func importPreview(current: [String], imported: [String]) -> (added: Int, overlapping: Int, machineOnly: Int) {
        let currentSet = Set(current)
        let importedSet = Set(imported)
        let added = importedSet.subtracting(currentSet).count
        let overlapping = importedSet.intersection(currentSet).count
        let machineOnly = currentSet.subtracting(importedSet).count
        return (added, overlapping, machineOnly)
    }

    /// Bỏ cặp nháy kép bao ngoài, khớp cách `QuickTranslationRuleParser` chấp nhận `"mẫu" = "nghĩa"`.
    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }
}
