import Foundation

public protocol TrieDictionary {
    func findLongestMatch(text: String, startIndex: Int) -> (length: Int, value: String)?
}

extension Data {
    func readInt32BE(at offset: Int) -> Int32 {
        guard offset + 4 <= self.count else { return 0 }
        let value = self.subdata(in: offset..<(offset + 4)).withUnsafeBytes { pointer in
            pointer.load(as: Int32.self)
        }
        return Int32(bigEndian: value)
    }
    
    func readUInt16BE(at offset: Int) -> UInt16 {
        guard offset + 2 <= self.count else { return 0 }
        let value = self.subdata(in: offset..<(offset + 2)).withUnsafeBytes { pointer in
            pointer.load(as: UInt16.self)
        }
        return UInt16(bigEndian: value)
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
    
    public init() {}
    
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
        
        self.base = Array(repeating: 0, count: baseLen)
        self.check = Array(repeating: 0, count: baseLen)
        
        for i in 0..<baseLen {
            self.base[i] = fileData.readInt32BE(at: baseByteOffset + i * 4)
            self.check[i] = fileData.readInt32BE(at: checkByteOffset + i * 4)
        }
        
        let poolSize = Int(fileData.readInt32BE(at: afterCheckOffset))
        self.stringPoolOffset = afterCheckOffset + 4
        
        guard fileData.count >= self.stringPoolOffset + poolSize else {
            throw NSError(domain: "DoubleArrayTrie", code: -5, userInfo: [NSLocalizedDescriptionKey: "String pool is truncated"])
        }
        
        self.isLoaded = true
    }
    
    public func findLongestMatch(text: String, startIndex: Int) -> (length: Int, value: String)? {
        guard isLoaded, startIndex < text.count else { return nil }
        
        let utf16 = Array(text.utf16)
        
        var currentState: Int32 = 1
        var matchLen = -1
        var matchStringPoolOffset: Int32 = -1
        
        var currentIndex = startIndex
        let textLen = utf16.count
        
        while currentIndex < textLen {
            let charVal = Int(utf16[currentIndex])
            let charCode = charVal < 65536 ? fastCharMap[charVal] : 0
            if charCode == 0 { break }
            
            let nextState = base[Int(currentState)] + charCode
            if nextState < 0 || nextState >= baseLen || check[Int(nextState)] != currentState {
                break
            }
            
            let termState = base[Int(nextState)]
            if termState >= 0 && termState < baseLen && check[Int(termState)] == nextState {
                matchStringPoolOffset = base[Int(termState)]
                matchLen = currentIndex - startIndex + 1
            }
            
            currentState = nextState
            currentIndex += 1
        }
        
        if matchLen > 0 && matchStringPoolOffset >= 0 {
            let absOffset = stringPoolOffset + Int(matchStringPoolOffset)
            guard absOffset + 2 <= data.count else { return nil }
            
            let strLen = Int(data.readUInt16BE(at: absOffset))
            guard absOffset + 2 + strLen <= data.count else { return nil }
            
            let strData = data.subdata(in: (absOffset + 2)..<(absOffset + 2 + strLen))
            if let resultStr = String(data: strData, encoding: .utf8) {
                return (matchLen, resultStr)
            }
        }
        
        return nil
    }
}
