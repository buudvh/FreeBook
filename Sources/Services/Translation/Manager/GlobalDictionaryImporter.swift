import Foundation

/// Nhập / xoá / ghi lại **từ điển gốc dùng chung** (thẻ VietPhrase.txt / Name.txt / PhienAm.txt / Pronouns.txt ở Cài đặt
/// dịch thuật, danh sách Phiên âm / Pronouns) theo ba chế độ của `DataImportMode`. Lớp custom (từ đã sửa ở VP / Name
/// Chung — `CustomVietPhrase.txt` / `CustomNames.txt`) **không** bị đụng ở mọi đường.
///
/// **Chỉ gọi qua `GlobalDictionaryEditor`** (actor xếp hàng): mọi lượt ghi từ điển gốc — nhập từ thẻ, nhập từ danh sách,
/// sửa / xoá một hàng, xoá cả từ điển — chạy nối tiếp, lượt sau chỉ bắt đầu khi lượt trước đã ghi **và** nạp lại xong.
///
/// - `.replaceAll`: như đường cũ `TranslationManager.importDictionary(from:type:)` (dựng `.dat` từ file nhập; PhienAm: chép
///   nguyên file) nhưng dựng / chép vào **file tạm** rồi mới thay file cũ.
/// - `.overwriteExisting` ("Gộp": trùng khoá lấy nghĩa **mới**) / `.keepExisting` ("Chỉ thêm key mới": trùng khoá giữ nghĩa
///   **cũ**): đọc từ điển gốc **trên đĩa** (`.dat`, không thì `.txt`; PhienAm: file text) — không đọc bản đã nạp trong RAM
///   vì nó có thể cũ hơn file —, trộn với file nhập, dựng `.dat` mới vào file tạm rồi thay file cũ (bỏ `.txt` cùng tên nếu
///   còn), nạp lại. Duyệt từ điển cũ một lượt, chỉ dựng bảng băm cho **file nhập**. PhienAm nạp kiểu **sau thắng**
///   (`loadPhoneticMap`) ⇒ trộn theo bảng băm rồi ghi lại file (sắp theo khoá; comment của file cũ không giữ).
///
/// Thay file: file tạm tên duy nhất (UUID) cùng thư mục, `FileManager.replaceItemAt` khi đích đã có (không xoá đích trước —
/// app bị tắt giữa chừng thì vẫn còn bản cũ), chưa có thì `moveItem`. Service: không SwiftUI, không toast.
enum GlobalDictionaryImporter {
    /// Số liệu cho toast "thêm X, cập nhật Y". `.replaceAll`: `added` = số mục của file, `updated` = 0.
    struct Outcome: Sendable {
        let added: Int
        let updated: Int
        /// Số mục (khoá khác nhau) đọc được trong file nhập.
        let importedCount: Int
    }

    enum ImportError: LocalizedError {
        case unknownType(String)
        case emptyFile
        /// Có `.dat` nhưng không mở được — dừng, không ghi đè bằng một từ điển chỉ còn nội dung file nhập.
        case unreadableBase(String)
        /// Duyệt cây ra ít / nhiều mục hơn `wordCount` khai — dừng, không ghi lại một từ điển thiếu mục.
        case enumerationMismatch(name: String, expected: Int, actual: Int)

        var errorDescription: String? {
            switch self {
            case .unknownType(let type): return "Không rõ loại từ điển \"\(type)\"."
            case .emptyFile: return "File không có dòng \"từ=nghĩa\" nào hợp lệ."
            case .unreadableBase(let name): return "Không đọc được \(name) hiện có — dừng để không làm mất từ điển."
            case .enumerationMismatch(let name, let expected, let actual):
                return "Đọc \(name) ra \(actual) mục nhưng từ điển khai \(expected) — dừng để không ghi lại từ điển thiếu."
            }
        }
    }

    /// `type`: mã thẻ của màn Cài đặt dịch thuật — `vietphrase`, `names`, `pronouns`, `phienam`.
    static func importFile(at url: URL, type: String, mode: DataImportMode) async throws -> Outcome {
        let files = try fileNames(for: type)
        let isPhienAm = files.dat == nil
        let imported = try parseEntries(at: url, lastWins: isPhienAm)
        guard !imported.isEmpty else { throw ImportError.emptyFile }

        let manager = TranslationManager.shared
        let root = manager.translateDirectory
        let outcome = try await Task.detached(priority: .userInitiated) { () throws -> Outcome in
            if mode == .replaceAll {
                try replaceBase(from: url, files: files, root: root)
                return Outcome(added: imported.count, updated: 0, importedCount: imported.count)
            }
            return try mergeAndWrite(imported, files: files, mode: mode)
        }.value
        try await manager.loadAllDictionaries()
        manager.notifyDictionariesDidUpdate()
        AppLogger.shared.log("📥 [GlobalDictionary] Nhập \(type) (\(mode.rawValue)): thêm \(outcome.added), cập nhật \(outcome.updated)")
        return outcome
    }

    /// Xoá file gốc (`.txt` + `.dat`) của một từ điển chung rồi nạp lại. Lớp custom giữ nguyên.
    static func deleteBaseDictionary(type: String) async throws {
        let files = try fileNames(for: type)
        let manager = TranslationManager.shared
        let root = manager.translateDirectory
        for name in [files.txt, files.dat].compactMap({ $0 }) {
            let url = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        try await manager.loadAllDictionaries()
        manager.notifyDictionariesDidUpdate()
        AppLogger.shared.log("🗑️ [GlobalDictionary] Đã xoá từ điển gốc \(type)")
    }

    /// Từ điển gốc **trên đĩa** của một loại (trộn khi nhập, danh sách sửa thẳng PhienAm / Pronouns).
    static func baseEntries(type: String) throws -> [(key: String, value: String)] {
        try existingEntries(files: fileNames(for: type), root: TranslationManager.shared.translateDirectory)
    }

    /// Ghi lại **cả** từ điển gốc từ danh sách mục: `.dat` dựng vào file tạm rồi thay file cũ (bỏ `.txt` cùng tên nếu
    /// còn); PhienAm ghi file text sắp theo khoá. Danh sách rỗng ⇒ xoá file gốc. Bên gọi tự nạp lại + báo đổi từ điển.
    static func writeBase(_ entries: [(key: String, value: String)], type: String) throws {
        try write(entries, files: fileNames(for: type), root: TranslationManager.shared.translateDirectory)
    }

    // MARK: - Phụ trợ

    /// Tên file trong `translate/`. `dat == nil` ⇒ từ điển dạng text (PhienAm).
    private static func fileNames(for type: String) throws -> (txt: String, dat: String?) {
        switch type {
        case "vietphrase": return ("VietPhrase.txt", "VietPhrase.dat")
        case "names": return ("Names.txt", "Names.dat")
        case "pronouns": return ("Pronouns.txt", "Pronouns.dat")
        case "phienam": return ("ChinesePhienAmWords.txt", nil)
        default: throw ImportError.unknownType(type)
        }
    }

    /// Dòng `từ=nghĩa` (bỏ dòng trống, `#`, thiếu `=`, khoá / nghĩa rỗng) — cùng luật `DoubleArrayTrieBuilder.build(fromTxtFile:)`
    /// và `loadPhoneticMap`. Khoá trùng: `lastWins == false` giữ dòng đầu (như từ điển text khác), `true` lấy dòng sau.
    private static func parseEntries(at url: URL, lastWins: Bool) throws -> [(key: String, value: String)] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var entries: [(key: String, value: String)] = []
        var indexByKey: [String: Int] = [:]
        for line in content.components(separatedBy: .newlines) {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !clean.hasPrefix("#"), clean.contains("=") else { continue }
            let parts = clean.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            if let index = indexByKey[key] {
                if lastWins { entries[index].value = value }
            } else {
                indexByKey[key] = entries.count
                entries.append((key: key, value: value))
            }
        }
        return entries
    }

    /// "Thay thế toàn bộ": `.dat` dựng thẳng từ file nhập (như `importDictionary`), PhienAm chép nguyên file — vào file tạm
    /// rồi thay.
    private static func replaceBase(from url: URL, files: (txt: String, dat: String?), root: URL) throws {
        if let datName = files.dat {
            let temporary = temporaryURL(for: datName, in: root)
            do {
                try DoubleArrayTrieBuilder().build(fromTxtFile: url, toDatFile: temporary)
                try install(temporary, at: root.appendingPathComponent(datName))
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
            try? FileManager.default.removeItem(at: root.appendingPathComponent(files.txt))
        } else {
            let temporary = temporaryURL(for: files.txt, in: root)
            do {
                try FileManager.default.copyItem(at: url, to: temporary)
                try install(temporary, at: root.appendingPathComponent(files.txt))
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
        }
    }

    private static func mergeAndWrite(
        _ imported: [(key: String, value: String)],
        files: (txt: String, dat: String?),
        mode: DataImportMode
    ) throws -> Outcome {
        let root = TranslationManager.shared.translateDirectory
        var pending = Dictionary(imported.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        var merged: [(key: String, value: String)] = []
        var updated = 0

        for entry in try existingEntries(files: files, root: root) {
            guard let newValue = pending.removeValue(forKey: entry.key) else {
                merged.append(entry)
                continue
            }
            if mode == .overwriteExisting,
               DictionaryTextFileStore.normalizeMeaning(newValue) != DictionaryTextFileStore.normalizeMeaning(entry.value) {
                merged.append((key: entry.key, value: newValue))
                updated += 1
            } else {
                merged.append(entry)
            }
        }
        var added = 0
        for entry in imported where pending[entry.key] != nil {
            merged.append(entry)
            added += 1
        }

        try write(merged, files: files, root: root)
        return Outcome(added: added, updated: updated, importedCount: imported.count)
    }

    private static func write(
        _ entries: [(key: String, value: String)],
        files: (txt: String, dat: String?),
        root: URL
    ) throws {
        let fileManager = FileManager.default
        guard !entries.isEmpty else {
            for name in [files.txt, files.dat].compactMap({ $0 }) {
                let url = root.appendingPathComponent(name)
                if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            }
            return
        }
        if let datName = files.dat {
            let temporary = temporaryURL(for: datName, in: root)
            do {
                try DoubleArrayTrieBuilder().build(fromEntries: entries, toDatFile: temporary)
                try install(temporary, at: root.appendingPathComponent(datName))
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
            try? fileManager.removeItem(at: root.appendingPathComponent(files.txt))
        } else {
            let text = entries.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
            try Data(text.utf8).write(to: root.appendingPathComponent(files.txt), options: .atomic)
        }
    }

    /// File tạm cùng thư mục, tên duy nhất — hai lượt không bao giờ dùng chung một file tạm. Trước khi tạo, dọn file tạm
    /// sót của lượt bị tắt giữa chừng (các lượt đã xếp hàng nên lúc này không lượt nào khác đang dùng file tạm).
    private static func temporaryURL(for name: String, in root: URL) -> URL {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        for stale in names where stale.hasPrefix("\(name).importing-") {
            try? fileManager.removeItem(at: root.appendingPathComponent(stale))
        }
        return root.appendingPathComponent("\(name).importing-\(UUID().uuidString)")
    }

    /// Đưa file tạm vào chỗ file đích: đích đã có ⇒ `replaceItemAt` (không xoá đích trước); chưa có ⇒ `moveItem`.
    private static func install(_ temporary: URL, at destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    /// Từ điển gốc **trên đĩa**: `.dat` ⇒ `.txt`; PhienAm: file text (sau thắng). Chưa có ⇒ rỗng. Như
    /// `GlobalDictionaryTextExporter`: số mục duyệt được từ `.dat` phải khớp `wordCount` (doc của `TrieDictionary.allEntries`)
    /// — lệch thì dừng, vì danh sách này sẽ được ghi lại thành **cả** từ điển gốc.
    private static func existingEntries(files: (txt: String, dat: String?), root: URL) throws -> [(key: String, value: String)] {
        let fileManager = FileManager.default
        let txtURL = root.appendingPathComponent(files.txt)
        guard let datName = files.dat else {
            return fileManager.fileExists(atPath: txtURL.path) ? try parseEntries(at: txtURL, lastWins: true) : []
        }
        let datURL = root.appendingPathComponent(datName)
        if fileManager.fileExists(atPath: datURL.path) {
            let trie = DoubleArrayTrie()
            do {
                try trie.load(from: datURL)
            } catch {
                throw ImportError.unreadableBase(datName)
            }
            guard trie.isLoaded else { throw ImportError.unreadableBase(datName) }
            let entries = trie.allEntries()
            guard entries.count == trie.wordCount else {
                throw ImportError.enumerationMismatch(name: datName, expected: trie.wordCount, actual: entries.count)
            }
            return entries
        }
        return fileManager.fileExists(atPath: txtURL.path) ? try parseEntries(at: txtURL, lastWins: false) : []
    }
}
