import Foundation

/// Nhập / xoá **từ điển gốc dùng chung** (thẻ VietPhrase.txt / Name.txt / PhienAm.txt / Pronouns.txt ở Cài đặt dịch thuật)
/// theo ba chế độ của `DataImportMode`. Lớp custom (từ đã sửa ở VP / Name Chung — `CustomVietPhrase.txt` /
/// `CustomNames.txt`) **không** bị đụng ở mọi đường.
///
/// - `.replaceAll`: đúng đường cũ `TranslationManager.importDictionary(from:type:)` — xoá file đích, dựng lại `.dat` từ
///   file nhập (PhienAm: chép nguyên), nạp lại.
/// - `.overwriteExisting` ("Gộp": trùng khoá lấy nghĩa **mới**) / `.keepExisting` ("Chỉ thêm key mới": trùng khoá giữ nghĩa
///   **cũ**): đọc từ điển gốc đang có (cây đã nạp, không thì `.dat`, không thì `.txt` — như `GlobalDictionaryTextExporter`),
///   trộn với file nhập, dựng `.dat` mới từ danh sách đã trộn bằng `DoubleArrayTrieBuilder.build(fromEntries:)` vào file
///   tạm rồi thay file cũ (bỏ luôn `.txt` cùng tên nếu còn — loader ưu tiên `.dat`, để lại chỉ là rác), nạp lại.
///   Duyệt từ điển cũ một lượt, chỉ dựng bảng băm cho **file nhập** (VietPhrase cỡ triệu mục thì không dựng bảng băm
///   cho nó). PhienAm là text `ChinesePhienAmWords.txt`, nạp kiểu **sau thắng** (`loadPhoneticMap`) ⇒ trộn theo bảng
///   băm rồi ghi lại file (sắp theo khoá; comment của file cũ không giữ).
///
/// Chạy ngoài `MainActor` (phần nặng trong `Task.detached`). Service: không SwiftUI, không toast — bên gọi tự báo.
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

        var errorDescription: String? {
            switch self {
            case .unknownType(let type): return "Không rõ loại từ điển \"\(type)\"."
            case .emptyFile: return "File không có dòng \"từ=nghĩa\" nào hợp lệ."
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
        if mode == .replaceAll {
            try await manager.importDictionary(from: url, type: type)
            return Outcome(added: imported.count, updated: 0, importedCount: imported.count)
        }

        let outcome = try await Task.detached(priority: .userInitiated) {
            try mergeAndWrite(imported, files: files, mode: mode)
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

    /// Từ điển gốc đang có của một loại (dùng cho trộn khi nhập và cho danh sách sửa thẳng PhienAm / Pronouns).
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
            let destination = root.appendingPathComponent(datName)
            let temporary = root.appendingPathComponent(datName + ".importing")
            try? FileManager.default.removeItem(at: temporary)
            try DoubleArrayTrieBuilder().build(fromEntries: entries, toDatFile: temporary)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
            try? FileManager.default.removeItem(at: root.appendingPathComponent(files.txt))
        } else {
            let text = entries.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
            try Data(text.utf8).write(to: root.appendingPathComponent(files.txt), options: .atomic)
        }
    }

    /// Từ điển gốc đang có: cây đã nạp ⇒ `.dat` ⇒ `.txt`; PhienAm: bản đồ đã nạp ⇒ file text. Chưa có ⇒ rỗng.
    private static func existingEntries(files: (txt: String, dat: String?), root: URL) throws -> [(key: String, value: String)] {
        let manager = TranslationManager.shared
        let fileManager = FileManager.default
        let txtURL = root.appendingPathComponent(files.txt)
        guard let datName = files.dat else {
            let map = manager.phienAmMap
            if !map.isEmpty { return map.map { (key: $0.key, value: $0.value) } }
            return fileManager.fileExists(atPath: txtURL.path) ? try parseEntries(at: txtURL, lastWins: true) : []
        }
        let loaded: TrieDictionary?
        switch datName {
        case "VietPhrase.dat": loaded = manager.vietPhraseDict
        case "Names.dat": loaded = manager.namesDict
        default: loaded = manager.pronounsDict
        }
        if let loaded { return loaded.allEntries() }
        let datURL = root.appendingPathComponent(datName)
        if fileManager.fileExists(atPath: datURL.path) {
            let trie = DoubleArrayTrie()
            try trie.load(from: datURL)
            if trie.isLoaded { return trie.allEntries() }
        }
        return fileManager.fileExists(atPath: txtURL.path) ? try parseEntries(at: txtURL, lastWins: false) : []
    }
}
