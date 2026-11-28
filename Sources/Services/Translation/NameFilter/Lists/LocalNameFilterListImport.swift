import Foundation

/// Phần dùng chung của **"Nhập file"** ở ba màn danh sách của Lọc name local — Hậu tố, Tiền tố, Không phải name, cả Chung
/// lẫn Riêng truyện (anh Bửu 2026-11-28): kiểu kết quả, đọc + kiểm file, và phép trộn thuần (không I/O) cho các danh sách
/// lưu dạng mảng. Mỗi store chỉ còn đọc – trộn – ghi **một lần** `UserDefaults` dưới khoá của chính nó (file `+Import`
/// của từng store); lớp sửa đổi của Hậu tố / Tiền tố Chung trộn ở `LocalNameFilterSuffixOverrides.importLines`.
///
/// **Định dạng** = đúng thứ "Xuất file" ghi (`LocalNameFilterListExport` — đổi một bên phải đổi bên kia): hậu tố / tiền tố
/// mỗi dòng `chữ Hán=nghĩa|loại|vị trí[|off]` qua bộ đọc + luật kiểm `LocalNameFilterSuffixListParser` (cờ `|off` của file
/// gốc đọc được nhưng bỏ qua); Không phải name mỗi dòng một cụm theo luật `LocalNameFilterBlocklistStore.formatError`.
/// Dòng trống và dòng bắt đầu bằng `#` bỏ qua, BOM đầu file bỏ, dòng sai bị bỏ và đếm.
///
/// **Ba chế độ** (`DataImportMode`): Gộp = khoá đã có thì đè, chưa có thì thêm; Chỉ thêm key mới = khoá đã có giữ nguyên;
/// Thay thế toàn bộ = danh sách thành đúng nội dung file. File không có dòng hợp lệ nào ⇒ lỗi, **không ghi gì** (tránh
/// "Thay thế toàn bộ" bằng file rỗng xoá sạch danh sách).
///
/// Ranh giới tầng: Service ⇒ không `import SwiftUI`, không `ToastManager`; View tự hiện toast từ `Outcome` / `Failure`.
enum LocalNameFilterListImport {
    typealias AffixLine = LocalNameFilterSuffixListParser.Line
    typealias TermEntry = LocalNameFilterBlocklistStore.Entry
    typealias ImportResult = Result<Outcome, Failure>

    /// Số liệu một lượt nhập — View dựng toast "thêm X, cập nhật Y".
    struct Outcome: Equatable, Sendable {
        /// Khoá / cụm trước đó chưa có.
        let added: Int
        /// Khoá đã có mà nghĩa / loại / vị trí thực sự đổi (danh sách chỉ có khoá ⇒ luôn 0).
        let updated: Int
        /// Chỉ "Thay thế toàn bộ": số mục đang có mà file không có.
        let removed: Int
        /// Dòng sai dạng / sai luật bị bỏ qua.
        let skipped: Int

        /// "Đã nhập: thêm 3, cập nhật 2, bỏ 5 hậu tố cũ, bỏ qua 1 dòng lỗi". `unit` = danh từ đếm ("hậu tố", "cụm");
        /// `countsUpdates == false` (danh sách chỉ có khoá) ⇒ "Đã nhập: thêm 3 cụm".
        func summary(unit: String, countsUpdates: Bool = true) -> String {
            var message = countsUpdates ? "Đã nhập: thêm \(added), cập nhật \(updated)" : "Đã nhập: thêm \(added) \(unit)"
            if removed > 0 { message += ", bỏ \(removed) \(unit) cũ" }
            if skipped > 0 { message += ", bỏ qua \(skipped) dòng lỗi" }
            return message
        }
    }

    /// Lý do không nhập được — lời tiếng Việt cho toast. Đã trả lỗi thì danh sách chưa bị đụng tới.
    struct Failure: LocalizedError, Equatable, Sendable {
        let message: String

        var errorDescription: String? { message }

        static let unreadable = Failure(message: "Không đọc được file (cần file chữ UTF-8).")

        /// `unit` = danh từ của một mục ("hậu tố", "tiền tố", "cụm").
        static func noValidLine(unit: String, skipped: Int) -> Failure {
            Failure(message: skipped > 0
                ? "File không có \(unit) hợp lệ nào (bỏ qua \(skipped) dòng sai)."
                : "File không có \(unit) nào.")
        }
    }

    /// File hậu tố / tiền tố đã đọc: khoá không lặp (dòng sau cùng thắng), theo thứ tự file.
    struct AffixFile: Sendable {
        let lines: [AffixLine]
        let skipped: Int
    }

    /// File "Không phải name" đã đọc: cụm không lặp, theo thứ tự file.
    struct TermFile: Sendable {
        let terms: [String]
        let skipped: Int
    }

    /// Kết quả trộn một danh sách dạng mảng.
    struct Merged<Item> {
        let items: [Item]
        let added: Int
        let updated: Int
        let removed: Int

        func outcome(skipped: Int) -> Outcome {
            Outcome(added: added, updated: updated, removed: removed, skipped: skipped)
        }
    }

    // MARK: - Đọc file

    /// Đọc + kiểm file hậu tố / tiền tố. `noun` = "Hậu tố" / "Tiền tố" (lời lỗi).
    static func affixFile(at url: URL, noun: String) -> Result<AffixFile, Failure> {
        guard let text = readText(at: url) else { return .failure(.unreadable) }
        let parsed = LocalNameFilterSuffixListParser.parse(text)
        guard !parsed.lines.isEmpty else {
            return .failure(.noValidLine(unit: noun.lowercased(), skipped: parsed.invalidLineCount))
        }
        return .success(AffixFile(lines: parsed.lines, skipped: parsed.invalidLineCount))
    }

    /// Đọc + kiểm file "Không phải name".
    static func termFile(at url: URL) -> Result<TermFile, Failure> {
        guard let text = readText(at: url) else { return .failure(.unreadable) }
        let file = parseTerms(text)
        guard !file.terms.isEmpty else { return .failure(.noValidLine(unit: "cụm", skipped: file.skipped)) }
        return .success(file)
    }

    /// Mỗi dòng một cụm chữ Hán (bỏ khoảng trắng hai đầu). Dòng trống / dòng `#` bỏ qua; cụm sai luật đếm vào `skipped`;
    /// cụm lặp lại trong file chỉ lấy lần đầu (không tính là dòng lỗi).
    static func parseTerms(_ text: String) -> TermFile {
        var terms: [String] = []
        var seen = Set<String>()
        var skipped = 0
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        // `\r\n` tách thành một dòng thật + một dòng rỗng — dòng rỗng bị bỏ qua như dòng trống.
        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard LocalNameFilterBlocklistStore.formatError(line) == nil else {
                skipped += 1
                continue
            }
            if seen.insert(line).inserted { terms.append(line) }
        }
        return TermFile(terms: terms, skipped: skipped)
    }

    /// UTF-8 trước, không được thì UTF-16 (như các chỗ nhập file khác). Bộ chọn file chạy chế độ bản sao nên không cần
    /// quyền truy cập theo phạm vi.
    private static func readText(at url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .utf16))
    }

    // MARK: - Trộn (thuần)

    /// Trộn danh sách có khoá `current` (thứ tự đang lưu) với `imported` (thứ tự file, khoá **không lặp**):
    /// - **Thay thế toàn bộ**: kết quả = `imported`; "cập nhật" = khoá đã có mà mục khác đi, "bỏ" = khoá cũ vắng trong file.
    /// - **Gộp**: mục đã có mà khác ⇒ thay **tại chỗ** (tính "cập nhật"); khoá mới đứng đầu theo thứ tự file.
    /// - **Chỉ thêm key mới**: mục đã có giữ nguyên; khoá mới đứng đầu theo thứ tự file.
    static func merge<Item: Equatable>(
        current: [Item],
        imported: [Item],
        mode: DataImportMode,
        key: (Item) -> String
    ) -> Merged<Item> {
        var currentByKey: [String: Item] = [:]
        for item in current { currentByKey[key(item)] = item }
        var added = 0
        var updated = 0

        switch mode {
        case .replaceAll:
            var importedKeys = Set<String>()
            for item in imported {
                let itemKey = key(item)
                importedKeys.insert(itemKey)
                if let old = currentByKey[itemKey] {
                    if old != item { updated += 1 }
                } else {
                    added += 1
                }
            }
            let removed = currentByKey.keys.filter { !importedKeys.contains($0) }.count
            return Merged(items: imported, added: added, updated: updated, removed: removed)

        case .overwriteExisting, .keepExisting:
            var replacements: [String: Item] = [:]
            var fresh: [Item] = []
            for item in imported {
                let itemKey = key(item)
                guard let old = currentByKey[itemKey] else {
                    fresh.append(item)
                    added += 1
                    continue
                }
                if mode == .overwriteExisting, old != item {
                    replacements[itemKey] = item
                    updated += 1
                }
            }
            let kept = current.map { replacements[key($0)] ?? $0 }
            return Merged(items: fresh + kept, added: added, updated: updated, removed: 0)
        }
    }

    /// Trộn danh sách "Không phải name": cụm vốn có giữ **ngày thêm cũ** ở cả ba chế độ (nên "Gộp" và "Chỉ thêm key mới"
    /// cho cùng kết quả, không có gì để "cập nhật"), cụm mới lấy `now`.
    static func mergeTerms(
        current: [TermEntry],
        terms: [String],
        mode: DataImportMode,
        now: Date = Date()
    ) -> Merged<TermEntry> {
        var existing: [String: TermEntry] = [:]
        for entry in current where existing[entry.term] == nil { existing[entry.term] = entry }
        let imported = terms.map { existing[$0] ?? TermEntry(term: $0, addedAt: now) }
        return merge(current: current, imported: imported, mode: mode) { $0.term }
    }

    /// Lỗi vượt trần số cụm của danh sách "Không phải name" (`LocalNameFilterBlocklistStore.maxCount`).
    static func tooManyTerms(_ count: Int) -> Failure {
        let limit = LocalNameFilterBlocklistStore.maxCount
        return Failure(message: "Nhập xong danh sách sẽ có \(count) cụm, quá trần \(limit) cụm — bớt cụm trong file hoặc xoá bớt rồi nhập lại.")
    }
}
