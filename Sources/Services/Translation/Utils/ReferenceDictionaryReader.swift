import Foundation

/// Đọc ba từ điển **tham chiếu** để hiển thị: phiên âm Hán-Việt, đại từ (Pronouns), luật nhân (LuatNhan).
///
/// Vì sao cần lớp riêng thay vì dùng `DictionaryCache`: ba bộ này khác VietPhrase/Names ở hai điểm.
/// Chúng **không có bản riêng theo truyện** và không đi qua đường CRUD một-từ — `TranslationManager`
/// nói rõ mọi thao tác CRUD không đụng tới các file `.dat` chung và `ChinesePhienAmWords.txt`.
/// Ngoài ra `DoubleArrayTrie` **không** liệt kê được entry (chỉ có `wordCount` và tra cứu), nên muốn
/// hiện danh sách thì phải đọc lại file `.txt`.
public enum ReferenceDictionaryReader {

    public enum Kind: String, CaseIterable, Identifiable {
        case phienAm
        case pronouns
        case luatNhan

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .phienAm: return "Phiên âm Hán-Việt"
            case .pronouns: return "Đại từ (Pronouns)"
            case .luatNhan: return "Luật nhân (LuatNhan)"
            }
        }

        public var icon: String {
            switch self {
            case .phienAm: return "character.book.closed"
            case .pronouns: return "person.2.circle"
            case .luatNhan: return "function"
            }
        }

        /// Tên file `.txt` để liệt kê entry.
        public var textFileName: String {
            switch self {
            case .phienAm: return "ChinesePhienAmWords.txt"
            case .pronouns: return "Pronouns.txt"
            case .luatNhan: return "LuatNhan.txt"
            }
        }

        /// Số entry đã nạp vào RAM, kể cả khi chỉ có bản `.dat`.
        public var loadedCount: Int {
            let manager = TranslationManager.shared
            switch self {
            case .phienAm: return manager.phienAmMap.count
            case .pronouns: return manager.pronounsDict?.wordCount ?? 0
            case .luatNhan: return manager.luatNhanDict?.wordCount ?? 0
            }
        }
    }

    /// Kết quả đọc: entry đã sắp theo khoá, kèm lý do khi rỗng.
    public struct Outcome: Sendable {
        public let entries: [DictEntry]
        /// Có file `.txt` để liệt kê hay không. `false` mà `loadedCount > 0` nghĩa là chỉ có `.dat`.
        public let hasTextFile: Bool
    }

    public static func load(_ kind: Kind) -> Outcome {
        // Phiên âm luôn nạp từ `.txt` vào một map trong RAM, nên lấy thẳng ở đó là chính xác nhất.
        if kind == .phienAm {
            let map = TranslationManager.shared.phienAmMap
            if !map.isEmpty {
                let entries = map
                    .sorted { $0.key < $1.key }
                    .map { DictEntry(key: $0.key, value: $0.value) }
                return Outcome(entries: entries, hasTextFile: true)
            }
        }

        let url = TranslationManager.shared.translateDirectory
            .appendingPathComponent(kind.textFileName)
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return Outcome(entries: [], hasTextFile: false)
        }

        var entries: [DictEntry] = []
        entries.reserveCapacity(4096)
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<separator])
                .trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            entries.append(DictEntry(key: key, value: value))
        }
        return Outcome(entries: entries.sorted { $0.key < $1.key }, hasTextFile: true)
    }
}
