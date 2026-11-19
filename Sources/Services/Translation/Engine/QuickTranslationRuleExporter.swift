import Foundation

/// Xuất **một file** bộ rule của một phạm vi, **bỏ** rule đang tắt: dòng rule có mẫu nằm trong danh sách tắt của
/// chính phạm vi đó (chung ⇒ file tắt chung, tên chương ⇒ file tắt tên chương, riêng ⇒ file tắt của truyện) không vào
/// file. Danh sách tắt không còn xuất riêng.
///
/// Lọc **từng dòng** trên văn bản gốc của bộ rule nên comment, dòng trống và thứ tự dòng giữ nguyên. Mẫu của dòng lấy
/// bằng `QuickTranslationRuleParser.splitRuleLine` (như `QuickTranslationRuleRecordStore`), rồi chuẩn hoá bằng
/// `QuickTranslationRuleDisableFile.normalizedPattern` — **y** cách file tắt chuẩn hoá mẫu.
///
/// Dùng chung cho: ngăn kéo "…" của danh sách rule (cả ba bộ), "Chia sẻ bộ rule riêng sang truyện khác"
/// (`QuickTranslationRuleTransfer.shareBookRules`) và thẻ "Rule dịch" ở Cài đặt dịch thuật. Service: không SwiftUI,
/// không toast — trả `Outcome`, View tự báo.
public enum QuickTranslationRuleExporter {
    /// Văn bản đã lọc + số liệu để View báo.
    public struct Export: Sendable {
        public let text: String
        /// Số dòng rule còn lại trong file.
        public let ruleCount: Int
        /// Số dòng rule bị bỏ vì đang tắt.
        public let skippedDisabled: Int
    }

    public enum Outcome: Sendable {
        case file(URL, ruleCount: Int, skippedDisabled: Int)
        /// Phạm vi chưa có file rule.
        case noRuleSet
        /// Có file nhưng mọi rule đều đang tắt — không xuất file rỗng.
        case allDisabled(count: Int)
        case failure(message: String)
    }

    /// Tên file xuất = tên file trên máy của bộ đó.
    public static func fileName(for scope: QuickTranslationRuleScope) -> String {
        switch scope {
        case .global: return QuickTranslationRuleStore.ruleFileName
        case .chapterTitle: return QuickTranslationRuleChapterStore.ruleFileName
        case .book: return QuickTranslationRuleBookStore.ruleFileName
        }
    }

    /// Văn bản đã bỏ rule tắt của một phạm vi. `nil` = phạm vi chưa có file rule.
    public static func export(scope: QuickTranslationRuleScope) -> Export? {
        let source: String?
        switch scope {
        case .global: source = QuickTranslationRuleStore.shared.currentSourceText()
        case .chapterTitle: source = QuickTranslationRuleChapterStore.shared.currentSourceText()
        case .book(let bookId): source = QuickTranslationRuleBookStore.shared.currentSourceText(for: bookId)
        }
        guard let source else { return nil }
        let disabled = Set(QuickTranslationRuleDisableStore.shared.disabledPatterns(for: scope))
        return filtered(source, disabledPatterns: disabled)
    }

    /// Ghi file tạm (thư mục tạm của hệ thống, tên = `fileName(for:)`) để chia sẻ. Bên gọi tự xoá sau khi chia sẻ xong
    /// nếu muốn; ghi đè bản cũ cùng tên.
    public static func writeTemporaryFile(scope: QuickTranslationRuleScope) -> Outcome {
        guard let export = export(scope: scope) else { return .noRuleSet }
        guard export.ruleCount > 0 else { return .allDisabled(count: export.skippedDisabled) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(for: scope))
        do {
            try Data(export.text.utf8).write(to: url, options: .atomic)
            return .file(url, ruleCount: export.ruleCount, skippedDisabled: export.skippedDisabled)
        } catch {
            return .failure(message: "Lỗi xuất file: \(error.localizedDescription)")
        }
    }

    /// Bỏ mọi dòng rule có mẫu (đã chuẩn hoá như file tắt) thuộc `disabledPatterns`; dòng khác giữ nguyên văn.
    static func filtered(_ text: String, disabledPatterns: Set<String>) -> Export {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var kept: [String] = []
        kept.reserveCapacity(lines.count)
        var ruleCount = 0
        var skipped = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRuleLine(trimmed), let split = QuickTranslationRuleParser.splitRuleLine(trimmed) else {
                kept.append(line)
                continue
            }
            if disabledPatterns.contains(QuickTranslationRuleDisableFile.normalizedPattern(split.pattern)) {
                skipped += 1
                continue
            }
            ruleCount += 1
            kept.append(line)
        }
        return Export(text: kept.joined(separator: "\n"), ruleCount: ruleCount, skippedDisabled: skipped)
    }

    /// Cùng bộ tiền tố comment với `QuickTranslationRuleRecordStore` / `QuickTranslationRuleDisableFile`.
    private static func isRuleLine(_ trimmed: String) -> Bool {
        !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("//") && !trimmed.hasPrefix("===")
    }
}
