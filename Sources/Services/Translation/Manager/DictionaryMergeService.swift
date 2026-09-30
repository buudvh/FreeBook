import Foundation

/// Gộp `CustomVietPhrase.txt` (từ chỉnh sửa + tombstone) vào **một file text mới** `VietPhraseMerged.txt`.
///
/// **Cố ý không** ghi thẳng vào `VietPhrase.dat`. Chốt với user 2026-09-30: bước gộp chỉ **đọc** rồi sinh
/// ra một file text để người dùng xem/xuất trước, còn việc áp vào từ điển gốc là một hành động **do người
/// dùng chọn** và đi qua đường đã có (`TranslationManager.importDictionary` → `DoubleArrayTrieBuilder`).
/// Nhờ vậy một lỗi ở bước gộp **không** thể làm hỏng từ điển: nó chỉ tạo ra một file sai mà người dùng
/// thấy được trước khi quyết định.
///
/// Vì sao phải duyệt cây: sau lần chạy đầu, app xoá `VietPhrase.txt` sau khi biên dịch `.dat`
/// (`TranslationManager.loadAllDictionaries`), nên nguồn duy nhất còn lại của từ điển gốc là file nhị phân.
enum DictionaryMergeService {

    /// Tên file kết quả, nằm cùng thư mục `translate/` với các từ điển khác.
    static let mergedFileName = "VietPhraseMerged.txt"

    /// Tên file sao lưu `.dat` cũ, tạo **trước** khi nhập file gộp vào từ điển gốc.
    static let backupFileName = "VietPhrase.dat.bak-merge"

    struct Outcome: Equatable, Sendable {
        let fileURL: URL
        /// Số entry đọc được từ từ điển gốc — để đối chiếu với `wordCount`.
        let baseCount: Int
        /// Số từ chỉnh sửa của người dùng được áp vào.
        let customCount: Int
        /// Số tombstone bị loại khỏi kết quả.
        let deletedCount: Int
        /// Tổng số dòng của file kết quả.
        let totalCount: Int
    }

    enum MergeError: LocalizedError {
        case baseMissing
        /// Duyệt cây ra số entry khác `wordCount` ⇒ phép duyệt sai, **không** được dùng kết quả.
        case enumerationMismatch(expected: Int, actual: Int)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .baseMissing:
                return "Chưa nạp được từ điển VietPhrase gốc — hãy tải từ điển trước khi gộp."
            case .enumerationMismatch(let expected, let actual):
                return "Đọc từ điển gốc ra \(actual) từ nhưng file khai \(expected) — dừng lại để không ghi đè bằng dữ liệu thiếu."
            case .emptyResult:
                return "Kết quả gộp rỗng — không tạo file."
            }
        }
    }

    static func mergedFileURL() -> URL {
        TranslationManager.shared.translateDirectory.appendingPathComponent(mergedFileName)
    }

    /// Đọc từ điển gốc + custom, áp tombstone, ghi file kết quả. Chạy được ngoài `MainActor`.
    ///
    /// - Parameter progress: 0…1, gọi vài lần (không phải theo từng record — vòng lặp đã là O(n) trên
    ///   mảng trong RAM, báo theo mốc đủ để thanh tiến độ nhích).
    static func merge(progress: (Double) -> Void) throws -> Outcome {
        let manager = TranslationManager.shared
        guard let base = manager.vietPhraseDict else { throw MergeError.baseMissing }

        let baseEntries = base.allEntries()
        guard baseEntries.count == base.wordCount, !baseEntries.isEmpty else {
            throw MergeError.enumerationMismatch(expected: base.wordCount, actual: baseEntries.count)
        }
        progress(0.45)

        let customURL = manager.customTextURL(isName: false, bookId: nil)
        let customRecords = (try? DictionaryTextFileStore.parseRecords(from: customURL)) ?? []
        var overrides: [String: String] = [:]
        var tombstones = Set<String>()
        for record in customRecords {
            if record.isDeleted {
                tombstones.insert(record.key)
            } else {
                overrides[record.key] = record.value
            }
        }
        progress(0.55)

        var merged: [(key: String, value: String)] = []
        merged.reserveCapacity(baseEntries.count + overrides.count)
        var appliedCustomKeys = Set<String>()
        for entry in baseEntries {
            if tombstones.contains(entry.key) { continue }
            if let override = overrides[entry.key] {
                merged.append((key: entry.key, value: override))
                appliedCustomKeys.insert(entry.key)
            } else {
                merged.append(entry)
            }
        }
        // Từ chỉnh sửa **chưa có** trong gốc thì nối vào cuối; giữ nguyên thứ tự gốc cho phần còn lại để
        // file kết quả khác file gốc đúng ở những dòng thực sự đổi.
        for (key, value) in overrides where !appliedCustomKeys.contains(key) {
            merged.append((key: key, value: value))
        }
        progress(0.85)
        guard !merged.isEmpty else { throw MergeError.emptyResult }

        let text = merged.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        let destination = mergedFileURL()
        let temporary = destination.deletingPathExtension()
            .appendingPathExtension("tmp")
        try text.write(to: temporary, atomically: true, encoding: .utf8)
        // `replaceItemAt` để lần gộp sau không bao giờ đọc phải file viết dở.
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        progress(1.0)

        return Outcome(
            fileURL: destination,
            baseCount: baseEntries.count,
            customCount: overrides.count,
            deletedCount: tombstones.count,
            totalCount: merged.count
        )
    }
}
