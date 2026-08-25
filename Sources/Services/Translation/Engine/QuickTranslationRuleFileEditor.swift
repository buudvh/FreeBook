import Foundation

/// Phẫu thuật **theo dòng** trên văn bản file rule. Thêm/sửa địa chỉ hoá theo key (mẫu bên trái dấu `=`),
/// còn xoá nhận đúng dòng đã được snapshot/revision bảo vệ.
///
/// Vì sao không sinh lại file từ danh sách rule đã parse: làm vậy là mất comment (kể cả 11 dòng
/// header đặc tả DSL) và xáo thứ tự dòng — mà thứ tự dòng là tiebreak cuối của priority. Ở đây chỉ
/// đúng một dòng bị thay/xoá/thêm, mọi dòng khác nguyên văn.
///
/// Ngữ nghĩa **giống hệt từ điển** (`DictionaryCache.upsertEntry` / `updateKey` / `deleteEntry`):
/// - thêm mà key đã có ⇒ **đè nghĩa** (vế phải), giữ nguyên vị trí dòng nên priority không đổi;
/// - xoá ⇒ **xoá hẳn dòng**;
/// - sửa key ⇒ xử như **thêm key mới**, dòng cũ **giữ nguyên** (đúng như `updateKey`: "if newKey !=
///   oldKey, keep oldKey, upsert newKey").
public enum QuickTranslationRuleFileEditor {
    /// Kết quả sửa kèm toạ độ thay đổi để Store giữ handle UI của các hàng không liên quan.
    public struct Edit: Sendable {
        public enum Kind: Sendable {
            case inserted(sourceLine: Int)
            case replaced(sourceLine: Int, previousPattern: String, previousReplacement: String)
            case deleted(sourceLine: Int, pattern: String, replacement: String)
            case unchanged
        }

        public let text: String
        public let kind: Kind

        public init(text: String, kind: Kind) {
            self.text = text
            self.kind = kind
        }
    }

    /// Thêm rule mới hoặc đè nghĩa của key đã có.
    public static func upsert(pattern: String, replacement: String, in text: String) -> Edit {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return Edit(text: text, kind: .unchanged) }

        var lines = split(text)
        let formatted = format(pattern: key, replacement: replacement)

        if let index = indexOfRule(key: key, in: lines),
           let previous = QuickTranslationRuleParser.splitRuleLine(
               lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
           ) {
            lines[index] = formatted
            return Edit(
                text: lines.joined(separator: "\n"),
                kind: .replaced(
                    sourceLine: index + 1,
                    previousPattern: previous.pattern,
                    previousReplacement: previous.replacement
                )
            )
        }

        // Rule người dùng tự thêm đứng **trên** bộ tải về (nhưng dưới khối comment header): trùng mọi
        // tiêu chí priority thì dòng sớm hơn thắng, nên đây là cách "rule của tôi thắng rule mặc
        // định" mà không phải thêm khái niệm ưu tiên mới. Cùng tinh thần `insert(at: 0)` của từ điển.
        let index = insertionIndex(in: lines)
        lines.insert(formatted, at: index)
        return Edit(text: lines.joined(separator: "\n"), kind: .inserted(sourceLine: index + 1))
    }

    /// Xoá đúng dòng đã chọn. Không fallback theo key để rule trùng mẫu vẫn xoá đúng hàng đã vuốt.
    public static func delete(
        sourceLine: Int,
        expectedPattern: String,
        expectedReplacement: String,
        from text: String
    ) -> Edit? {
        var lines = split(text)
        let index = sourceLine - 1
        guard lines.indices.contains(index) else { return nil }
        let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isRuleLine(trimmed),
              let rule = QuickTranslationRuleParser.splitRuleLine(trimmed),
              rule.pattern == expectedPattern,
              rule.replacement == expectedReplacement else { return nil }
        lines.remove(at: index)
        return Edit(
            text: lines.joined(separator: "\n"),
            kind: .deleted(sourceLine: sourceLine, pattern: rule.pattern, replacement: rule.replacement)
        )
    }

    /// Sửa một rule. Đổi key ⇒ giữ dòng cũ và thêm key mới, đúng ngữ nghĩa `DictionaryCache.updateKey`.
    public static func update(
        oldPattern: String,
        newPattern: String,
        replacement: String,
        in text: String
    ) -> Edit {
        upsert(pattern: newPattern, replacement: replacement, in: text)
    }

    /// Nghĩa hiện tại của một key, để sheet sửa điền sẵn.
    public static func replacement(of pattern: String, in text: String) -> String? {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        for line in split(text) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRuleLine(trimmed),
                  let split = QuickTranslationRuleParser.splitRuleLine(trimmed),
                  split.pattern == key else { continue }
            return split.replacement
        }
        return nil
    }

    // MARK: - Nhập theo 3 chế độ

    /// Trộn văn bản file nhập vào văn bản đang có, khoá so trùng là **mẫu bên trái dấu `=`**.
    ///
    /// Hai chế độ trộn đều **giữ nguyên thứ tự dòng của bản trên máy** (thứ tự dòng là tiebreak cuối
    /// của priority, đảo là đổi kết quả dịch ở những chỗ trùng độ ưu tiên) và **giữ nguyên comment**
    /// của cả hai bên: dòng comment của file nhập chỉ theo vào cùng các rule mới ở cuối.
    /// Rule mới nối vào **cuối file** — khác `upsert` của CRUD tay (chèn lên đầu): nhập file là "bổ
    /// sung bộ của người khác", không nên vượt lên trước những rule người dùng đã tự viết.
    public static func merge(current: String, imported: String, mode: DataImportMode) -> String {
        guard mode != .replaceAll else { return imported }

        let currentLines = split(current)
        var result = currentLines
        var indexByKey: [String: Int] = [:]
        for (index, line) in currentLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRuleLine(trimmed),
                  let split = QuickTranslationRuleParser.splitRuleLine(trimmed) else { continue }
            // Trùng key trong chính file cũ ⇒ dòng đầu tiên là dòng đang thắng, chỉ đè lên nó.
            if indexByKey[split.pattern] == nil { indexByKey[split.pattern] = index }
        }

        var appended: [String] = []
        var seenImportedKeys = Set<String>()

        for line in split(imported) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRuleLine(trimmed),
                  let split = QuickTranslationRuleParser.splitRuleLine(trimmed) else { continue }
            guard seenImportedKeys.insert(split.pattern).inserted else { continue }

            if let index = indexByKey[split.pattern] {
                if mode == .overwriteExisting {
                    result[index] = format(pattern: split.pattern, replacement: split.replacement)
                }
                continue
            }
            appended.append(format(pattern: split.pattern, replacement: split.replacement))
        }

        guard !appended.isEmpty else { return result.joined(separator: "\n") }
        if let last = result.last, !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append("")
        }
        result.append("# --- Rule nhập thêm ---")
        result.append(contentsOf: appended)
        return result.joined(separator: "\n")
    }

    /// Đếm trước khi nhập, để dialog nói rõ "thêm N / cập nhật M / giữ K" thay vì chỉ nói tên chế độ.
    public static func importPreview(current: String, imported: String) -> (added: Int, overlapping: Int, machineOnly: Int) {
        var currentKeys = Set<String>()
        for line in split(current) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRuleLine(trimmed),
                  let split = QuickTranslationRuleParser.splitRuleLine(trimmed) else { continue }
            currentKeys.insert(split.pattern)
        }

        var importedKeys = Set<String>()
        for line in split(imported) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRuleLine(trimmed),
                  let split = QuickTranslationRuleParser.splitRuleLine(trimmed) else { continue }
            importedKeys.insert(split.pattern)
        }

        let overlapping = currentKeys.intersection(importedKeys).count
        return (
            added: importedKeys.count - overlapping,
            overlapping: overlapping,
            machineOnly: currentKeys.count - overlapping
        )
    }

    // MARK: - Phụ trợ

    /// Chuẩn hoá về `\n` khi đọc; file được ghi lại toàn bộ nên CRLF của bản tải về không sống sót —
    /// chấp nhận được vì parser tự chuẩn hoá `\r\n` và `\r` ở chiều đọc.
    private static func split(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// Chỉ số dòng **đầu tiên** mang key này. Trùng key là lỗi file (xoá bớt một dòng ở nguồn là
    /// hết), và dòng đầu tiên cũng chính là dòng đang thắng ở runtime — nên sửa/xoá nhắm vào nó.
    private static func indexOfRule(key: String, in lines: [String]) -> Int? {
        guard !key.isEmpty else { return nil }
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRuleLine(trimmed),
                  let split = QuickTranslationRuleParser.splitRuleLine(trimmed),
                  split.pattern == key else { continue }
            return index
        }
        return nil
    }

    /// Chèn ngay **sau** khối comment/dòng trống ở đầu file để không đẩy header đặc tả DSL xuống dưới.
    private static func insertionIndex(in lines: [String]) -> Int {
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.hasPrefix("===") {
                index += 1
                continue
            }
            break
        }
        return index
    }

    private static func isRuleLine(_ trimmed: String) -> Bool {
        !trimmed.isEmpty
            && !trimmed.hasPrefix("#")
            && !trimmed.hasPrefix("//")
            && !trimmed.hasPrefix("===")
    }

    /// Một khuôn duy nhất cho dòng do app ghi: `mẫu = bản dịch`, không bọc ngoặc kép (parser đọc
    /// được cả hai dạng, nhưng dạng trần dễ đọc và khớp với 3 bộ rule thật).
    private static func format(pattern: String, replacement: String) -> String {
        let value = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(pattern) = \(value)"
    }
}
