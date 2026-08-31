import Foundation

/// Đọc từ điển nhị phân `sea_g2p.bin` (~62.8 MB) của sea-g2p.
///
/// Định dạng: header 32 byte, một pool chuỗi NUL-terminated, rồi hai bảng đã **sắp sẵn** để tra
/// bằng tìm kiếm nhị phân — `merged` (từ → phoneme) và `common` (từ → cặp phoneme Việt/Anh cho các
/// từ đồng dạng hai ngôn ngữ).
///
/// File được `mmap` chứ không nạp vào heap: 62.8 MB nằm ở page cache file-backed, chỉ những trang
/// thật sự bị tra mới vào RAM.
///
/// Hai điểm khác bản thử nghiệm:
///
/// 1. **So sánh theo byte UTF-8**, không dựng `String` cho mỗi lần probe. Bảng được Rust sắp theo
///    thứ tự byte của `&str`; `String` của Swift so sánh sau khi chuẩn hoá Unicode nên với chuỗi
///    có dấu thì thứ tự có thể lệch khỏi thứ tự mà bảng được sắp — tìm kiếm nhị phân sẽ **trượt**
///    một số từ mà không báo lỗi. Bỏ luôn 17 lần cấp phát `String` cho mỗi lần tra.
/// 2. **Có lock.** Cache nằm trong instance và `prepare()` (warm-up nền) có thể chạy song song với
///    một lần tổng hợp.
final class SeaG2PDictionary: @unchecked Sendable {
    /// Kết quả tra bảng `common`: phoneme đọc theo tiếng Việt và theo tiếng Anh.
    struct CommonEntry {
        let vietnamese: String
        let english: String
    }

    private static let magic: [UInt8] = [0x53, 0x45, 0x41, 0x50] // "SEAP"
    private static let headerSize = 32

    private let data: Data
    private let stringCount: Int
    private let mergedCount: Int
    private let commonCount: Int
    private let stringOffsetsPosition: Int
    private let mergedPosition: Int
    private let commonPosition: Int

    private let lock = NSLock()
    private var mergedCache: [String: String] = [:]
    private var commonCache: [String: CommonEntry] = [:]
    private var mergedMisses: Set<String> = []
    private var commonMisses: Set<String> = []

    init(url: URL) throws {
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= Self.headerSize else {
            throw TTSError.internalError("sea_g2p.bin quá nhỏ (\(data.count) byte)")
        }
        guard Array(data[0..<4]) == Self.magic else {
            throw TTSError.internalError("sea_g2p.bin sai magic, không phải từ điển sea-g2p")
        }
        self.stringCount = Self.readUInt32(data, 8)
        self.mergedCount = Self.readUInt32(data, 12)
        self.commonCount = Self.readUInt32(data, 16)
        self.stringOffsetsPosition = Self.readUInt32(data, 20)
        self.mergedPosition = Self.readUInt32(data, 24)
        self.commonPosition = Self.readUInt32(data, 28)

        guard stringCount > 0, mergedPosition > 0, commonPosition > 0 else {
            throw TTSError.internalError("Header sea_g2p.bin không hợp lệ")
        }
    }

    // MARK: - Tra cứu có cache

    /// Từ → phoneme. Chuỗi trả về đã bỏ nhãn `<en>` và trim.
    func mergedPhoneme(for word: String) -> String? {
        let key = word.precomposedStringWithCanonicalMapping
        lock.lock()
        if let cached = mergedCache[key] { lock.unlock(); return cached }
        if mergedMisses.contains(key) { lock.unlock(); return nil }
        lock.unlock()

        let found = searchMerged(key)

        lock.lock()
        if let found {
            if mergedCache.count >= 10_000 { mergedCache.removeAll(keepingCapacity: true) }
            mergedCache[key] = found
        } else if mergedMisses.count < 50_000 {
            mergedMisses.insert(key)
        }
        lock.unlock()
        return found
    }

    /// Từ → cặp phoneme Việt/Anh.
    func commonEntry(for word: String) -> CommonEntry? {
        let key = word.precomposedStringWithCanonicalMapping
        lock.lock()
        if let cached = commonCache[key] { lock.unlock(); return cached }
        if commonMisses.contains(key) { lock.unlock(); return nil }
        lock.unlock()

        let found = searchCommon(key)

        lock.lock()
        if let found {
            if commonCache.count >= 5_000 { commonCache.removeAll(keepingCapacity: true) }
            commonCache[key] = found
        } else if commonMisses.count < 50_000 {
            commonMisses.insert(key)
        }
        lock.unlock()
        return found
    }

    // MARK: - Tìm kiếm nhị phân

    private func searchMerged(_ word: String) -> String? {
        let needle = Array(word.utf8)
        var low = 0
        var high = mergedCount - 1
        while low <= high {
            let mid = (low + high) / 2
            let entry = mergedPosition + mid * 8
            let order = compareStoredString(id: Self.readUInt32(data, entry), with: needle)
            if order == 0 {
                return cleanedString(id: Self.readUInt32(data, entry + 4))
            } else if order < 0 {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }

    private func searchCommon(_ word: String) -> CommonEntry? {
        let needle = Array(word.utf8)
        var low = 0
        var high = commonCount - 1
        while low <= high {
            let mid = (low + high) / 2
            let entry = commonPosition + mid * 12
            let order = compareStoredString(id: Self.readUInt32(data, entry), with: needle)
            if order == 0 {
                return CommonEntry(
                    vietnamese: cleanedString(id: Self.readUInt32(data, entry + 4)),
                    english: cleanedString(id: Self.readUInt32(data, entry + 8))
                )
            } else if order < 0 {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }

    // MARK: - Pool chuỗi

    private func stringRange(id: Int) -> Range<Int>? {
        guard id >= 0 && id < stringCount else { return nil }
        let offsetPointer = stringOffsetsPosition + id * 4
        let start = Self.headerSize + Self.readUInt32(data, offsetPointer)
        guard start < data.count else { return nil }
        var end = start
        while end < data.count && data[end] != 0 { end += 1 }
        return start..<end
    }

    /// So sánh chuỗi trong pool với `needle` theo **byte**: âm nếu chuỗi trong pool nhỏ hơn.
    private func compareStoredString(id: Int, with needle: [UInt8]) -> Int {
        guard let range = stringRange(id: id) else { return 1 }
        var index = range.lowerBound
        var position = 0
        while index < range.upperBound && position < needle.count {
            let stored = data[index]
            let query = needle[position]
            if stored != query { return stored < query ? -1 : 1 }
            index += 1
            position += 1
        }
        let storedRemaining = range.upperBound - index
        let queryRemaining = needle.count - position
        if storedRemaining == queryRemaining { return 0 }
        return storedRemaining < queryRemaining ? -1 : 1
    }

    /// Chuỗi trong pool, đã bỏ nhãn `<en>` và trim — dạng mà mọi call site đều cần.
    private func cleanedString(id: Int) -> String {
        rawString(id: id)
            .replacingOccurrences(of: "<en>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Chuỗi thô, còn nhãn `<en>` — dùng để biết một từ được coi là tiếng Anh hay tiếng Việt.
    func rawString(id: Int) -> String {
        guard let range = stringRange(id: id) else { return "" }
        return String(decoding: data[range], as: UTF8.self)
    }

    /// Bản thô của `merged` — cần nhãn `<en>` để quyết định ngôn ngữ của token.
    func mergedRawPhoneme(for word: String) -> String? {
        let needle = Array(word.precomposedStringWithCanonicalMapping.utf8)
        var low = 0
        var high = mergedCount - 1
        while low <= high {
            let mid = (low + high) / 2
            let entry = mergedPosition + mid * 8
            let order = compareStoredString(id: Self.readUInt32(data, entry), with: needle)
            if order == 0 {
                return rawString(id: Self.readUInt32(data, entry + 4))
            } else if order < 0 {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> Int {
        guard offset + 4 <= data.count else { return 0 }
        return Int(data[offset])
            | (Int(data[offset + 1]) << 8)
            | (Int(data[offset + 2]) << 16)
            | (Int(data[offset + 3]) << 24)
    }
}
