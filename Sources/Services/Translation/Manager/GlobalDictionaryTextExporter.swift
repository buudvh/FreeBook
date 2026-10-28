import Foundation

/// Xuất một từ điển **chung** (thẻ ở Cài đặt dịch thuật › Từ điển chung) ra file `.txt` tạm để chia sẻ (1.3.638).
///
/// Xuất **đúng file gốc** (người dùng chọn): không kèm từ đã thêm/xoá ở VP/Name Chung — bản đó đã có nút Gộp. Nhập lại
/// file xuất qua chính thẻ đó cho ra từ điển y như cũ.
///
/// - VietPhrase / Name / Pronouns / LuatNhan: sau lần nạp đầu app chỉ còn `.dat` nhị phân (`loadAllDictionaries` xoá
///   `.txt`) ⇒ duyệt ngược cây bằng `allEntries()`, mỗi dòng `từ=nghĩa` như `DictionaryMergeService`. Số entry duyệt
///   được phải khớp `wordCount`, lệch thì báo lỗi chứ không xuất file thiếu.
/// - PhienAm: `ChinesePhienAmWords.txt` vốn là text ⇒ chép nguyên.
///
/// Chạy được ngoài `MainActor` (đọc `TranslationManager` giống `DictionaryMergeService.merge`). Caller tự xoá file tạm
/// sau khi chia sẻ xong.
enum GlobalDictionaryTextExporter {
    enum ExportError: LocalizedError {
        case unknownType(String)
        case notAvailable(String)
        case enumerationMismatch(name: String, expected: Int, actual: Int)

        var errorDescription: String? {
            switch self {
            case .unknownType(let type):
                return "Không rõ loại từ điển \"\(type)\"."
            case .notAvailable(let name):
                return "Chưa có dữ liệu \(name) để xuất."
            case .enumerationMismatch(let name, let expected, let actual):
                return "Đọc \(name) ra \(actual) từ nhưng từ điển khai \(expected) — dừng lại để không xuất file thiếu."
            }
        }
    }

    /// Một thẻ từ điển: tên file xuất, file `.dat`/`.txt` trong `translate/` và cây đang nạp (nếu có).
    private struct Source {
        let exportPrefix: String
        let datFileName: String?
        let txtFileName: String
        let loaded: TrieDictionary?
    }

    /// Ghi ra đĩa theo từng khúc ~1 MB thay vì dựng một chuỗi khổng lồ (VietPhrase cỡ trăm nghìn – triệu dòng).
    private static let writeChunkBytes = 1 << 20

    /// `type` dùng đúng mã của màn Cài đặt dịch thuật: `vietphrase`, `names`, `phienam`, `pronouns`, `luatnhan`.
    static func export(type: String) throws -> URL {
        let manager = TranslationManager.shared
        let source = try source(for: type, manager: manager)
        let destination = temporaryURL(prefix: source.exportPrefix)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        let dictionary: TrieDictionary
        if let loaded = source.loaded {
            dictionary = loaded
        } else if let datFileName = source.datFileName,
                  fileManager.fileExists(atPath: manager.translateDirectory.appendingPathComponent(datFileName).path) {
            let trie = DoubleArrayTrie()
            try trie.load(from: manager.translateDirectory.appendingPathComponent(datFileName))
            guard trie.isLoaded else { throw ExportError.notAvailable(source.exportPrefix) }
            dictionary = trie
        } else {
            // PhienAm, hoặc `.txt` vừa tải về mà chưa kịp biên dịch sang `.dat`: chép nguyên file text.
            let textURL = manager.translateDirectory.appendingPathComponent(source.txtFileName)
            guard fileManager.fileExists(atPath: textURL.path) else {
                throw ExportError.notAvailable(source.exportPrefix)
            }
            try fileManager.copyItem(at: textURL, to: destination)
            return destination
        }

        let entries = dictionary.allEntries()
        guard !entries.isEmpty else { throw ExportError.notAvailable(source.exportPrefix) }
        guard entries.count == dictionary.wordCount else {
            throw ExportError.enumerationMismatch(
                name: source.exportPrefix,
                expected: dictionary.wordCount,
                actual: entries.count
            )
        }
        try write(entries, to: destination)
        return destination
    }

    private static func source(for type: String, manager: TranslationManager) throws -> Source {
        switch type {
        case "vietphrase":
            return Source(exportPrefix: "VietPhrase", datFileName: "VietPhrase.dat", txtFileName: "VietPhrase.txt",
                          loaded: manager.vietPhraseDict)
        case "names":
            return Source(exportPrefix: "Name", datFileName: "Names.dat", txtFileName: "Names.txt",
                          loaded: manager.namesDict)
        case "pronouns":
            return Source(exportPrefix: "Pronouns", datFileName: "Pronouns.dat", txtFileName: "Pronouns.txt",
                          loaded: manager.pronounsDict)
        case "luatnhan":
            return Source(exportPrefix: "LuatNhan", datFileName: "LuatNhan.dat", txtFileName: "LuatNhan.txt",
                          loaded: manager.luatNhanDict)
        case "phienam":
            return Source(exportPrefix: "PhienAm", datFileName: nil, txtFileName: "ChinesePhienAmWords.txt",
                          loaded: nil)
        default:
            throw ExportError.unknownType(type)
        }
    }

    private static func temporaryURL(prefix: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        let fileName = "\(prefix)_\(formatter.string(from: Date())).txt"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private static func write(_ entries: [(key: String, value: String)], to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        var chunk = ""
        chunk.reserveCapacity(writeChunkBytes + 1024)
        for entry in entries {
            chunk += entry.key
            chunk += "="
            chunk += entry.value
            chunk += "\n"
            if chunk.utf8.count >= writeChunkBytes {
                try handle.write(contentsOf: Data(chunk.utf8))
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            try handle.write(contentsOf: Data(chunk.utf8))
        }
    }
}
