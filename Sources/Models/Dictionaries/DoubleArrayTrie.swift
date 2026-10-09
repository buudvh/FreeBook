import Foundation

public protocol TrieDictionary {
    func frozen() -> FrozenTrieDictionary
    func findLongestMatch(text: String, startIndex: Int) -> (length: Int, value: String)?
    func findAllPrefixMatches(text: String, startIndex: Int) -> [(length: Int, value: String)]
    /// Chỉ độ dài của các khớp tiền tố — cùng tập với `findAllPrefixMatches(...)` nhưng không dựng nghĩa
    /// (tokenizer chỉ đọc độ dài). Mặc định suy ra từ `findAllPrefixMatches`.
    func prefixMatchLengths(text: String, startIndex: Int) -> [Int]
    var wordCount: Int { get }
    /// Duyệt **toàn bộ** entry (khoá + nghĩa), không phụ thuộc kho đang giữ text hay `.dat` nhị phân.
    ///
    /// Cần cho việc gộp từ điển: kho gốc `VietPhrase.dat` không có nguồn text sau lần biên dịch đầu
    /// (`TranslationManager.loadAllDictionaries` xoá `VietPhrase.txt`), nên chỉ còn cách duyệt ngược cây.
    /// Caller **phải** tự so `allEntries().count` với `wordCount` trước khi dùng kết quả để ghi đè.
    func allEntries() -> [(key: String, value: String)]
}

extension TrieDictionary {
    public func prefixMatchLengths(text: String, startIndex: Int) -> [Int] {
        findAllPrefixMatches(text: text, startIndex: startIndex).map { $0.length }
    }
}

// Đọc từng byte theo chỉ số tuyệt đối (giống `subdata(in:)` cũ) thay vì cắt một `Data` tạm cho mỗi lần đọc.
extension Data {
    func readInt32BE(at offset: Int) -> Int32 {
        guard offset + 4 <= self.count else { return 0 }
        let byte0 = UInt32(self[offset]), byte1 = UInt32(self[offset + 1])
        let byte2 = UInt32(self[offset + 2]), byte3 = UInt32(self[offset + 3])
        return Int32(bitPattern: (byte0 << 24) | (byte1 << 16) | (byte2 << 8) | byte3)
    }
    
    func readUInt16BE(at offset: Int) -> UInt16 {
        guard offset + 2 <= self.count else { return 0 }
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }
}

public final class DoubleArrayTrie: TrieDictionary {
    private var base: [Int32] = []
    private var check: [Int32] = []
    private var fastCharMap: [Int32] = Array(repeating: 0, count: 65536)
    private var stringPoolOffset: Int = 0
    private var data: Data = Data()
    private var baseLen: Int = 0
    private var size: Int = 0
    public private(set) var isLoaded = false
    
    public var wordCount: Int {
        return size
    }
    
    public init() {}

    public func frozen() -> FrozenTrieDictionary {
        FrozenTrieDictionary(dat: .init(base: base, check: check, charMap: fastCharMap,
                                       data: data, poolOffset: stringPoolOffset, size: size))
    }
    
    public func load(from fileURL: URL) throws {
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        self.data = fileData
        
        guard fileData.count >= 24 else {
            throw NSError(domain: "DoubleArrayTrie", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid file size"])
        }
        
        // Parse Header
        let magic = fileData.readInt32BE(at: 0)
        let magicExpected: Int32 = 0x44415432
        guard magic == magicExpected else {
            throw NSError(domain: "DoubleArrayTrie", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid MAGIC header"])
        }
        
        let version = fileData.readInt32BE(at: 4)
        guard version == 3 else {
            throw NSError(domain: "DoubleArrayTrie", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unsupported version: \(version)"])
        }
        
        self.size = Int(fileData.readInt32BE(at: 8))
        self.baseLen = Int(fileData.readInt32BE(at: 12))
        let charMapSize = Int(fileData.readInt32BE(at: 16))
        
        var offset = 24
        
        // Read CharMap
        fastCharMap = Array(repeating: 0, count: 65536)
        for _ in 0..<charMapSize {
            let charCode = Int(fileData.readInt32BE(at: offset))
            let mappedCode = fileData.readInt32BE(at: offset + 4)
            offset += 8
            if charCode >= 0 && charCode < 65536 {
                fastCharMap[charCode] = mappedCode
            }
        }
        
        // Map base and check arrays
        let baseByteOffset = offset
        let checkByteOffset = baseByteOffset + baseLen * 4
        let afterCheckOffset = checkByteOffset + baseLen * 4
        
        guard fileData.count >= afterCheckOffset + 4 else {
            throw NSError(domain: "DoubleArrayTrie", code: -4, userInfo: [NSLocalizedDescriptionKey: "File is truncated"])
        }
        
        // Dựng hai mảng cục bộ trong một lượt `withUnsafeBytes` rồi gán **một** lần: ghi `self.base[i]` từng
        // phần tử qua thuộc tính class trả kiểm exclusivity/CoW mỗi vòng, cộng một lượt zero-fill thừa.
        // Vẫn là phép `load` căn lề cũ, nên mảng thu được giống từng bit.
        let count = baseLen
        let (loadedBase, loadedCheck) = fileData.withUnsafeBytes { rawBufferPointer -> ([Int32], [Int32]) in
            guard let baseAddress = rawBufferPointer.baseAddress else {
                return (Array(repeating: 0, count: count), Array(repeating: 0, count: count))
            }
            func loadBigEndianInt32s(from byteOffset: Int) -> [Int32] {
                [Int32](unsafeUninitializedCapacity: count) { buffer, initializedCount in
                    for i in 0..<count {
                        let raw = baseAddress.load(fromByteOffset: byteOffset + i * 4, as: Int32.self)
                        buffer[i] = Int32(bigEndian: raw)
                    }
                    initializedCount = count
                }
            }
            return (loadBigEndianInt32s(from: baseByteOffset), loadBigEndianInt32s(from: checkByteOffset))
        }
        self.base = loadedBase
        self.check = loadedCheck
        
        let poolSize = Int(fileData.readInt32BE(at: afterCheckOffset))
        self.stringPoolOffset = afterCheckOffset + 4
        
        guard fileData.count >= self.stringPoolOffset + poolSize else {
            throw NSError(domain: "DoubleArrayTrie", code: -5, userInfo: [NSLocalizedDescriptionKey: "String pool is truncated"])
        }
        
        self.isLoaded = true
    }
    
    public func findLongestMatch(text: String, startIndex: Int) -> (length: Int, value: String)? {
        guard isLoaded else { return nil }
        return frozen().findLongestMatch(text: text, startIndex: startIndex)
    }

    public func findAllPrefixMatches(text: String, startIndex: Int) -> [(length: Int, value: String)] {
        guard isLoaded else { return [] }
        return frozen().findAllPrefixMatches(text: text, startIndex: startIndex)
    }

    /// Uỷ quyền cho `FrozenTrieDictionary` — nơi giữ phần duyệt cây (xem doc ở protocol).
    public func allEntries() -> [(key: String, value: String)] {
        guard isLoaded else { return [] }
        return frozen().allEntries()
    }
    
}
