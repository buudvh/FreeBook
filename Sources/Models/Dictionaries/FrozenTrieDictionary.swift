import Foundation

/// Immutable lookup storage shared by translation tasks; loaders never mutate a published value.
public struct FrozenTrieDictionary: TrieDictionary, Sendable {
    internal struct DAT: Sendable {
        let base: [Int32]
        let check: [Int32]
        let charMap: [Int32]
        let data: Data
        let poolOffset: Int
        let size: Int
    }

    private let entries: [String: String]
    private let lengths: [Int]
    private let dat: DAT?

    internal init(entries: [String: String], lengths: [Int]) {
        self.entries = entries
        self.lengths = lengths
        self.dat = nil
    }

    internal init(dat: DAT) {
        self.entries = [:]
        self.lengths = []
        self.dat = dat
    }

    public var wordCount: Int { dat?.size ?? entries.count }
    public func frozen() -> FrozenTrieDictionary { self }

    public func findLongestMatch(text: String, startIndex: Int) -> (length: Int, value: String)? {
        if let dat { return trieMatches(text, at: startIndex, dat: dat, longestOnly: true).last }
        let units = Array(text.utf16)
        guard startIndex >= 0, startIndex < units.count else { return nil }
        for length in lengths where length <= units.count - startIndex {
            let key = String(decoding: units[startIndex..<(startIndex + length)], as: UTF16.self)
            if let value = entries[key] { return (length, value) }
        }
        return nil
    }

    public func findAllPrefixMatches(text: String, startIndex: Int) -> [(length: Int, value: String)] {
        if let dat { return trieMatches(text, at: startIndex, dat: dat, longestOnly: false) }
        let units = Array(text.utf16)
        guard startIndex >= 0, startIndex < units.count else { return [] }
        var result: [(length: Int, value: String)] = []
        for length in lengths where length <= units.count - startIndex {
            let key = String(decoding: units[startIndex..<(startIndex + length)], as: UTF16.self)
            if let value = entries[key] { result.append((length, value)) }
        }
        return result
    }

    private func trieMatches(
        _ text: String, at start: Int, dat: DAT, longestOnly: Bool
    ) -> [(length: Int, value: String)] {
        let units = Array(text.utf16)
        guard start >= 0, start < units.count else { return [] }
        var state = 1
        var terminals: [(length: Int, offset: Int)] = []
        for index in start..<units.count {
            let code = dat.charMap[Int(units[index])]
            guard code != 0, dat.base.indices.contains(state) else { break }
            let next = Int(dat.base[state]) + Int(code)
            guard dat.base.indices.contains(next), dat.check[next] == Int32(state) else { break }
            let term = Int(dat.base[next])
            if dat.base.indices.contains(term), dat.check[term] == Int32(next), dat.base[term] >= 0 {
                if longestOnly { terminals.removeAll(keepingCapacity: true) }
                terminals.append((index - start + 1, Int(dat.base[term])))
            }
            state = next
        }
        return terminals.compactMap { terminal in
            let offset = dat.poolOffset + terminal.offset
            guard offset >= 0, offset + 2 <= dat.data.count else { return nil }
            let length = Int(dat.data.readUInt16BE(at: offset))
            guard offset + 2 + length <= dat.data.count,
                  let value = String(data: dat.data.subdata(in: (offset + 2)..<(offset + 2 + length)), encoding: .utf8)
            else { return nil }
            return (terminal.length, value)
        }
    }
}
