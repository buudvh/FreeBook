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

    /// Duyệt **toàn bộ** entry (xem doc ở `TrieDictionary.allEntries`).
    ///
    /// Với kho `.dat`: cây được duyệt theo **đúng** phép tính chỉ số của `trieMatches` nhưng chiều ngược —
    /// cạnh `state → next` tồn tại khi `next = base[state] + code` và `check[next] == state`; nút kết thúc
    /// của `next` là `base[next]` khi `check[base[next]] == next` và `base[base[next]] >= 0`, giá trị nằm ở
    /// `poolOffset + base[base[next]]` (2 byte độ dài big-endian + UTF-8).
    ///
    /// Chỉ mục con dựng **một lượt** trước khi duyệt (gom slot theo `check[slot] > 0`): quét `charMap` cho
    /// từng nút là O(số nút × số ký tự) — không khả thi với từ điển thật. Mỗi nút chỉ giữ
    /// `(trạng thái, cha, mã nén)` và khoá được dựng bằng cách đi ngược lên cha, nên chỉ tốn O(độ sâu) cho
    /// mỗi **entry** thay vì copy mảng khoá ở mọi cạnh.
    ///
    /// **Tự kiểm**: caller phải so `allEntries().count` với `wordCount`; lệch nghĩa là phép duyệt sai.
    public func allEntries() -> [(key: String, value: String)] {
        guard let dat else {
            return entries.map { (key: $0.key, value: $0.value) }
        }

        // Slot chưa dùng giữ `check == 0`, nên `check[slot] > 0` chính là "slot này là con của trạng thái
        // `check[slot]`" (trạng thái 0 và 1 được đánh dấu `-1` nên không lọt vào đây).
        var childCount = [Int32](repeating: 0, count: dat.check.count)
        var totalChildren = 0
        for slot in 0..<dat.check.count where dat.check[slot] > 0 {
            childCount[Int(dat.check[slot])] += 1
            totalChildren += 1
        }
        var childOffset = [Int32](repeating: 0, count: dat.check.count + 1)
        var running = 0
        for state in 0..<childCount.count {
            childOffset[state] = Int32(running)
            running += Int(childCount[state])
        }
        childOffset[childCount.count] = Int32(running)
        var childSlots = [Int32](repeating: 0, count: totalChildren)
        // `childCount` đã hết việc ⇒ dùng lại nó làm **con trỏ điền** thay vì cấp thêm mảng thứ ba:
        // `base`/`check` của từ điển thật có thể tới hàng triệu slot, mỗi mảng bớt được là đáng.
        for state in 0..<childCount.count { childCount[state] = childOffset[state] }
        for slot in 0..<dat.check.count where dat.check[slot] > 0 {
            let parent = Int(dat.check[slot])
            childSlots[Int(childCount[parent])] = Int32(slot)
            childCount[parent] += 1
        }

        // Đảo `fastCharMap`: lúc tra chỉ cần mã điểm → mã nén, duyệt cây cần chiều ngược lại.
        let maxCode = Int(dat.charMap.max() ?? 0)
        var codePointByCode = [Int32](repeating: -1, count: maxCode + 1)
        for codePoint in 0..<dat.charMap.count where dat.charMap[codePoint] != 0 {
            codePointByCode[Int(dat.charMap[codePoint])] = Int32(codePoint)
        }

        var nodeState: [Int] = [1]
        var nodeParent: [Int] = [-1]
        var nodeCodePoint: [Int32] = [0]
        var stack: [Int] = [0]
        var results: [(key: String, value: String)] = []
        results.reserveCapacity(dat.size)

        while let nodeIndex = stack.popLast() {
            let state = nodeState[nodeIndex]
            for index in Int(childOffset[state])..<Int(childOffset[state + 1]) {
                let next = Int(childSlots[index])
                let code = next - Int(dat.base[state])
                guard code >= 0, code < codePointByCode.count else { continue }
                let codePoint = codePointByCode[code]
                guard codePoint >= 0 else { continue }

                let childIndex = nodeState.count
                nodeState.append(next)
                nodeParent.append(nodeIndex)
                nodeCodePoint.append(codePoint)

                let terminal = Int(dat.base[next])
                if dat.base.indices.contains(terminal),
                   dat.check[terminal] == Int32(next),
                   dat.base[terminal] >= 0 {
                    let offset = dat.poolOffset + Int(dat.base[terminal])
                    let length = Int(dat.data.readUInt16BE(at: offset))
                    if offset + 2 + length <= dat.data.count,
                       let value = String(
                           data: dat.data.subdata(in: (offset + 2)..<(offset + 2 + length)),
                           encoding: .utf8
                       ) {
                        // Node 0 là gốc (không có ký tự) nên vòng lặp dừng ở `cursor > 0`.
                        var units: [UInt16] = []
                        var cursor = childIndex
                        while cursor > 0 {
                            units.append(UInt16(nodeCodePoint[cursor]))
                            cursor = nodeParent[cursor]
                        }
                        results.append((String(decoding: units.reversed(), as: UTF16.self), value))
                    }
                }
                stack.append(childIndex)
            }
        }
        return results
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
