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

    /// Tên file meta kèm theo, **dẫn xuất** từ `mergedFileName` để không lệch tên nếu sau này đổi tên file gộp.
    static var mergedMetaFileName: String {
        (mergedFileName as NSString).deletingPathExtension + ".meta.json"
    }

    /// Tên file sao lưu `.dat` cũ, tạo **trước** khi nhập file gộp vào từ điển gốc.
    static let backupFileName = "VietPhrase.dat.bak-merge"

    /// Bản ghi số liệu của một lượt gộp, ghi **kèm** file kết quả.
    ///
    /// Vì sao tồn tại: `Outcome` đã biết chính xác mọi con số **ngay lúc ghi file**. Trước đây màn Thông báo
    /// suy lại chúng bằng cách đọc và parse toàn bộ `VietPhraseMerged.txt` (~1,4 triệu dòng) **trên main
    /// thread** mỗi lần render ⇒ đơ app và nghẽn luôn TTS. Ghi meta ra file riêng để lần sau chỉ cần
    /// `JSONDecoder` trên vài trăm byte.
    struct Meta: Codable, Equatable, Sendable {
        /// Phiên bản lược đồ. Gặp giá trị lạ ⇒ coi như **không có meta** (lùi về nhánh chậm), không crash.
        static let currentVersion = 1

        let version: Int
        let baseCount: Int
        let customCount: Int
        let deletedCount: Int
        let totalCount: Int
        /// Thời điểm sinh file — thay cho `attributesOfItem` khi cần ngày hiển thị.
        let createdAt: Date

        init(
            version: Int = Meta.currentVersion,
            baseCount: Int,
            customCount: Int,
            deletedCount: Int,
            totalCount: Int,
            createdAt: Date = Date()
        ) {
            self.version = version
            self.baseCount = baseCount
            self.customCount = customCount
            self.deletedCount = deletedCount
            self.totalCount = totalCount
            self.createdAt = createdAt
        }
    }

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

    static func mergedMetaURL() -> URL {
        TranslationManager.shared.translateDirectory.appendingPathComponent(mergedMetaFileName)
    }

    /// Ghi meta atomically (`tmp` + `replaceItemAt`), cùng khuôn với file kết quả.
    ///
    /// **Luôn gọi SAU khi file `.txt` đã ghi xong**: nếu meta hỏng thì trạng thái tệ nhất là "có file, thiếu
    /// meta" (UI lùi về nhánh chậm), chứ không bao giờ thành "có meta, thiếu file" (UI hiện mục mà không có
    /// gì để nhập).
    static func writeMeta(_ meta: Meta) {
        guard let data = try? JSONEncoder().encode(meta) else { return }
        let destination = mergedMetaURL()
        let temporary = destination.deletingPathExtension().appendingPathExtension("tmp")
        guard (try? data.write(to: temporary, options: .atomic)) != nil else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try? FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try? FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    /// Đọc meta kèm theo. File không tồn tại / decode lỗi / `version` lạ ⇒ `nil` (lùi về nhánh chậm),
    /// **không** parse `VietPhraseMerged.txt` để bù — đó chính là thứ từng gây đơ.
    static func loadMeta() -> Meta? {
        guard let data = try? Data(contentsOf: mergedMetaURL()),
              let meta = try? JSONDecoder().decode(Meta.self, from: data),
              meta.version == Meta.currentVersion else {
            return nil
        }
        return meta
    }

    /// Xoá meta — **luôn** gọi cùng lượt với xoá `VietPhraseMerged.txt` để không để lại meta mồ côi.
    static func deleteMeta() {
        try? FileManager.default.removeItem(at: mergedMetaURL())
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

        let outcome = Outcome(
            fileURL: destination,
            baseCount: baseEntries.count,
            customCount: overrides.count,
            deletedCount: tombstones.count,
            totalCount: merged.count
        )
        // Meta ghi **sau** file kết quả: hỏng meta ⇒ chỉ lùi về nhánh chậm, không mất dữ liệu.
        writeMeta(
            Meta(
                baseCount: outcome.baseCount,
                customCount: outcome.customCount,
                deletedCount: outcome.deletedCount,
                totalCount: outcome.totalCount
            )
        )
        return outcome
    }
}
