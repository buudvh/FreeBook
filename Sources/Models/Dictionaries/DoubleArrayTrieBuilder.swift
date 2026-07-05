import Foundation

public final class DoubleArrayTrieBuilder {
    public init() {}
    
    private struct Sibling {
        let code: Int32
        let left: Int
        let right: Int
        let depth: Int
    }
    
    // Biên dịch từ file .txt ra .dat nhị phân (với cơ chế chuẩn hóa nghĩa dịch bằng dấu /)
    public func build(fromTxtFile txtUrl: URL, toDatFile datUrl: URL) throws {
        let content = try String(contentsOf: txtUrl, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var rawEntries: [(key: String, value: String)] = []
        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty || clean.hasPrefix("#") { continue }
            guard clean.contains("=") else { continue }
            
            let parts = clean.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let val = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty && !val.isEmpty {
                    rawEntries.append((key: key, value: val))
                }
            }
        }
        
        try build(fromEntries: rawEntries, toDatFile: datUrl)
    }
    
    // Biên dịch trực tiếp từ mảng các entries dạng RAM ra .dat nhị phân
    public func build(fromEntries rawEntries: [(key: String, value: String)], toDatFile datUrl: URL) throws {
        var sortedEntries = rawEntries
        
        // 1. Chuẩn hóa các nghĩa dịch: split / và ¦, trim, sau đó join lại bằng /
        for i in 0..<sortedEntries.count {
            let rawVal = sortedEntries[i].value
            let cleanVal = rawVal.replacingOccurrences(of: "¦", with: "/")
            let parts = cleanVal.components(separatedBy: "/")
            let normalized = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                 .filter { !$0.isEmpty }
                                 .joined(separator: "/")
            sortedEntries[i].value = normalized
        }
        
        // Sắp xếp các khóa theo thứ tự từ điển (lexicographically)
        sortedEntries.sort { $0.key < $1.key }
        
        // Loại bỏ các key bị trùng lặp (giữ lại nghĩa của key xuất hiện trước)
        var entries: [(key: String, value: String)] = []
        var seenKeys = Set<String>()
        for entry in sortedEntries {
            if !seenKeys.contains(entry.key) {
                seenKeys.insert(entry.key)
                entries.append(entry)
            }
        }
        
        let size = entries.count
        
        // 2. Dựng bản đồ ký tự fastCharMap
        var charMap: [Int32: Int32] = [:]
        var nextCharCode: Int32 = 1
        for entry in entries {
            for char in entry.key.utf16 {
                let codePoint = Int32(char)
                if charMap[codePoint] == nil {
                    charMap[codePoint] = nextCharCode
                    nextCharCode += 1
                }
            }
        }
        
        // 3. Chuyển đổi các từ khóa thành mảng các mã ký tự
        var keysCodes: [[Int32]] = []
        keysCodes.reserveCapacity(size)
        for entry in entries {
            var codes: [Int32] = []
            codes.reserveCapacity(entry.key.utf16.count + 1)
            for char in entry.key.utf16 {
                codes.append(charMap[Int32(char)]!)
            }
            codes.append(0) // mã ký tự kết thúc chuỗi (terminal)
            keysCodes.append(codes)
        }
        
        // 4. Khởi tạo mảng BASE và CHECK với kích thước ban đầu
        var base: [Int32] = Array(repeating: 0, count: 65536)
        var check: [Int32] = Array(repeating: 0, count: 65536)
        
        // Đánh dấu trạng thái 0 là đã sử dụng
        check[0] = -1
        
        // 5. Khởi tạo String Pool để lưu nghĩa dịch tiếng Việt
        var stringPool = Data()
        var stringPoolOffsets: [Int: Int32] = [:]
        
        for i in 0..<size {
            let val = entries[i].value
            let valData = val.data(using: .utf8) ?? Data()
            let offset = Int32(stringPool.count)
            stringPoolOffsets[i] = offset
            
            var lenBE = UInt16(valData.count).bigEndian
            withUnsafeBytes(of: &lenBE) { stringPool.append($0) }
            stringPool.append(valData)
        }
        
        // Hàm tự động mở rộng kích thước mảng BASE/CHECK
        func ensureCapacity(forIndex idx: Int) {
            if idx >= base.count {
                let newCapacity = max(idx + 1, base.count * 2)
                base.append(contentsOf: Array(repeating: Int32(0), count: newCapacity - base.count))
                check.append(contentsOf: Array(repeating: Int32(0), count: newCapacity - check.count))
            }
        }
        
        // Hàm dựng Trie đệ quy
        var nextCheckPos: Int = 1
        
        func buildTrie(parentState: Int, siblings: [Sibling]) {
            var baseValue = nextCheckPos
            let maxCode = siblings.map { $0.code }.max() ?? 0
            
            outerLoop: while true {
                ensureCapacity(forIndex: baseValue + Int(maxCode))
                
                for sib in siblings {
                    let childState = baseValue + Int(sib.code)
                    if check[childState] != 0 {
                        baseValue += 1
                        continue outerLoop
                    }
                }
                break
            }
            
            if parentState == 1 {
                nextCheckPos = baseValue
            }
            
            base[parentState] = Int32(baseValue)
            
            for sib in siblings {
                let childState = baseValue + Int(sib.code)
                check[childState] = Int32(parentState)
            }
            
            for sib in siblings {
                let childState = baseValue + Int(sib.code)
                
                if sib.code == 0 {
                    let entryIdx = sib.left
                    base[childState] = stringPoolOffsets[entryIdx]!
                } else {
                    var childSiblings: [Sibling] = []
                    var left = sib.left
                    while left <= sib.right {
                        let codes = keysCodes[left]
                        let nextDepth = sib.depth + 1
                        let nextCode = codes[nextDepth]
                        
                        var right = left
                        while right + 1 <= sib.right && keysCodes[right + 1][nextDepth] == nextCode {
                            right += 1
                        }
                        
                        childSiblings.append(Sibling(code: nextCode, left: left, right: right, depth: nextDepth))
                        left = right + 1
                    }
                    
                    buildTrie(parentState: childState, siblings: childSiblings)
                }
            }
        }
        
        // Khởi tạo các sibling gốc (độ sâu 0)
        var initialSiblings: [Sibling] = []
        var left = 0
        while left < size {
            let nextCode = keysCodes[left][0]
            var right = left
            while right + 1 < size && keysCodes[right + 1][0] == nextCode {
                right += 1
            }
            initialSiblings.append(Sibling(code: nextCode, left: left, right: right, depth: 0))
            left = right + 1
        }
        
        if size > 0 {
            buildTrie(parentState: 1, siblings: initialSiblings)
        }
        
        // Trim mảng BASE và CHECK tới chỉ mục lớn nhất có sử dụng
        var maxUsedIndex = 0
        for i in (0..<check.count).reversed() {
            if check[i] != 0 {
                maxUsedIndex = i
                break
            }
        }
        let baseLen = maxUsedIndex + 1
        
        // 6. Tuần tự hóa nhị phân (Binary Serialization)
        var outputData = Data()
        
        var magic = Int32(0x44415432).bigEndian // "DAT2"
        var version = Int32(3).bigEndian
        var sizeBE = Int32(size).bigEndian
        var baseLenBE = Int32(baseLen).bigEndian
        var charMapSizeBE = Int32(charMap.count).bigEndian
        
        withUnsafeBytes(of: &magic) { outputData.append($0) }
        withUnsafeBytes(of: &version) { outputData.append($0) }
        withUnsafeBytes(of: &sizeBE) { outputData.append($0) }
        withUnsafeBytes(of: &baseLenBE) { outputData.append($0) }
        withUnsafeBytes(of: &charMapSizeBE) { outputData.append($0) }
        
        var reserved = Int32(0).bigEndian
        withUnsafeBytes(of: &reserved) { outputData.append($0) }
        
        // Ghi CharMap
        let sortedCharMap = charMap.sorted { $0.key < $1.key }
        for entry in sortedCharMap {
            var charCode = Int32(entry.key).bigEndian
            var mappedCode = Int32(entry.value).bigEndian
            withUnsafeBytes(of: &charCode) { outputData.append($0) }
            withUnsafeBytes(of: &mappedCode) { outputData.append($0) }
        }
        
        // Ghi BASE
        for i in 0..<baseLen {
            var val = base[i].bigEndian
            withUnsafeBytes(of: &val) { outputData.append($0) }
        }
        
        // Ghi CHECK
        for i in 0..<baseLen {
            var val = check[i].bigEndian
            withUnsafeBytes(of: &val) { outputData.append($0) }
        }
        
        // Ghi PoolSize
        var poolSize = Int32(stringPool.count).bigEndian
        withUnsafeBytes(of: &poolSize) { outputData.append($0) }
        
        // Ghi String Pool
        outputData.append(stringPool)
        
        // Ghi xuống file đích
        try outputData.write(to: datUrl, options: .atomic)
    }
}
