import Foundation

/// Chỉ mục duyệt của **từ điển gốc** VietPhrase.dat / Names.dat cho danh sách `GlobalBaseDictionaryListView` (1.3.1037,
/// anh Bửu: "vietphrase tìm quá lâu, hiển thị ra cũng lâu"). Dựng **một lần** mỗi lần mở màn và giữ khoá dạng đơn vị
/// UTF-16 nối liền một mảng + vị trí nghĩa trong pool — không dựng `String` cho từng mục (cỡ triệu mục), nên mở màn,
/// lật trang và tìm theo khoá / nghĩa (`BaseDictionaryIndexSearch`) không phải duyệt lại cây.
///
/// Thứ tự = tiền thứ tự của cây như `FrozenTrieDictionary.walkEntries`: khoá cha trước khoá con, anh em theo mã nén tăng.
/// Phép duyệt **chép riêng** (cùng phép tính cạnh `next = base[state] + code`, `check[next] == state`; nút kết thúc
/// `base[next]` khi `check[base[next]] == next` và `base[base[next]] >= 0`) chứ không đi qua `walkEntries`: hàm đó nuôi
/// `allEntries` của nhập / gộp từ điển (số mục phải khớp `wordCount`), đừng đổi nó vì danh sách. Khác một điểm: **không**
/// kiểm nghĩa giải mã được UTF-8 lúc dựng (builder luôn ghi UTF-8 hợp lệ; kiểm là đọc hết pool) — nghĩa hỏng chỉ hiện
/// rỗng (`meaning(at:)` = nil) và không khớp khi tìm theo nghĩa.
final class BaseDictionaryIndex: Sendable {
    /// Đơn vị UTF-16 của mọi khoá nối liền; khoá `i` = `keyUnits[keyStart[i]..<keyStart[i + 1]]`.
    let keyUnits: [UInt16]
    let keyStart: [Int32]
    /// Vị trí (tuyệt đối trong `valueData`) của nghĩa khoá `i`: 2 byte độ dài big-endian + UTF-8, như pool của `.dat`.
    let valueOffset: [Int32]
    /// Bản `.dat` đã map (kho `.dat`) hoặc pool tự dựng cùng khuôn (kho `entries`).
    let valueData: Data

    var count: Int { valueOffset.count }

    private init(keyUnits: [UInt16], keyStart: [Int32], valueOffset: [Int32], valueData: Data) {
        self.keyUnits = keyUnits
        self.keyStart = keyStart
        self.valueOffset = valueOffset
        self.valueData = valueData
    }

    func key(at index: Int) -> String {
        String(decoding: keyUnits[Int(keyStart[index])..<Int(keyStart[index + 1])], as: UTF16.self)
    }

    func keys(in range: Range<Int>) -> [String] {
        range.map { key(at: $0) }
    }

    /// Vùng byte UTF-8 của nghĩa khoá `index` trong `valueData`; `nil` khi vượt dữ liệu.
    func valueRange(at index: Int) -> Range<Int>? {
        Self.valueRange(at: Int(valueOffset[index]), dataCount: valueData.count) { valueData[$0] }
    }

    func meaning(at index: Int) -> String? {
        guard let range = valueRange(at: index) else { return nil }
        return String(bytes: valueData[range], encoding: .utf8)
    }

    /// Như `FrozenTrieDictionary.poolValueRange`, đọc byte qua `byteAt` để dùng được cả với con trỏ thô khi tìm.
    static func valueRange(at offset: Int, dataCount: Int, byteAt: (Int) -> UInt8) -> Range<Int>? {
        guard offset >= 0, offset + 2 <= dataCount else { return nil }
        let length = (Int(byteAt(offset)) << 8) | Int(byteAt(offset + 1))
        guard offset + 2 + length <= dataCount else { return nil }
        return (offset + 2)..<(offset + 2 + length)
    }

    // MARK: - Dựng

    /// Dựng chỉ mục; `onFirstPage` gọi **một lần** (trên luồng đang dựng) khi đã có `firstPageSize` khoá đầu — màn hiện
    /// trang đầu trong lúc dựng nốt. Không huỷ giữa chừng: việc có chặn trên, màn bỏ dở thì kết quả bị bỏ.
    static func build(
        from dictionary: FrozenTrieDictionary,
        firstPageSize: Int,
        onFirstPage: ([String]) -> Void
    ) -> BaseDictionaryIndex {
        if let dat = dictionary.dat {
            return build(dat: dat, firstPageSize: firstPageSize, onFirstPage: onFirstPage)
        }
        return build(entries: dictionary.entries, firstPageSize: firstPageSize, onFirstPage: onFirstPage)
    }

    private static func build(
        dat: FrozenTrieDictionary.DAT,
        firstPageSize: Int,
        onFirstPage: ([String]) -> Void
    ) -> BaseDictionaryIndex {
        var keyUnits: [UInt16] = []
        keyUnits.reserveCapacity(dat.size * 4)
        var keyStart: [Int32] = [0]
        keyStart.reserveCapacity(dat.size + 1)
        var valueOffset: [Int32] = []
        valueOffset.reserveCapacity(dat.size)

        let slotCount = min(dat.base.count, dat.check.count)
        guard slotCount > 1 else {
            return BaseDictionaryIndex(keyUnits: [], keyStart: [0], valueOffset: [], valueData: dat.data)
        }

        // Đảo `charMap`: tra cần mã điểm → mã nén, duyệt cây cần chiều ngược lại.
        let maxCode = Int(dat.charMap.max() ?? 0)
        var unitByCode = [Int32](repeating: -1, count: maxCode + 1)
        for codePoint in 0..<dat.charMap.count where dat.charMap[codePoint] > 0 {
            unitByCode[Int(dat.charMap[codePoint])] = Int32(codePoint)
        }

        dat.base.withUnsafeBufferPointer { base in
            dat.check.withUnsafeBufferPointer { check in
                // Chỉ mục con dựng một lượt: con của `state` = `childSlots[childOffset[state]..<childOffset[state + 1]]`,
                // theo slot tăng ⇒ theo mã nén tăng.
                var childOffset = [Int32](repeating: 0, count: slotCount + 1)
                for slot in 0..<slotCount {
                    let parent = Int(check[slot])
                    if parent > 0, parent < slotCount { childOffset[parent + 1] += 1 }
                }
                for state in 0..<slotCount { childOffset[state + 1] += childOffset[state] }
                var cursor = Array(childOffset[0..<slotCount])
                var childSlots = [Int32](repeating: 0, count: Int(childOffset[slotCount]))
                for slot in 0..<slotCount {
                    let parent = Int(check[slot])
                    guard parent > 0, parent < slotCount else { continue }
                    childSlots[Int(cursor[parent])] = Int32(slot)
                    cursor[parent] += 1
                }
                cursor = []

                var path: [UInt16] = []
                path.reserveCapacity(64)
                // Khung gốc (trạng thái 1) không ứng với ký tự nào; mọi khung khác ứng với đơn vị cuối của `path`.
                var stack: [(state: Int, cursor: Int)] = [(1, Int(childOffset[1]))]
                while let top = stack.last {
                    if top.cursor >= Int(childOffset[top.state + 1]) {
                        stack.removeLast()
                        if !stack.isEmpty { path.removeLast() }
                        continue
                    }
                    stack[stack.count - 1].cursor += 1
                    let next = Int(childSlots[top.cursor])
                    let code = next - Int(base[top.state])
                    guard code >= 0, code < unitByCode.count, unitByCode[code] >= 0 else { continue }
                    path.append(UInt16(unitByCode[code]))

                    let terminal = Int(base[next])
                    if terminal >= 0, terminal < slotCount, check[terminal] == Int32(next), base[terminal] >= 0 {
                        keyUnits.append(contentsOf: path)
                        keyStart.append(Int32(keyUnits.count))
                        valueOffset.append(Int32(dat.poolOffset + Int(base[terminal])))
                        if valueOffset.count == firstPageSize {
                            onFirstPage(firstKeys(keyUnits: keyUnits, keyStart: keyStart))
                        }
                    }
                    stack.append((next, Int(childOffset[next])))
                }
            }
        }
        if valueOffset.count < firstPageSize {
            onFirstPage(firstKeys(keyUnits: keyUnits, keyStart: keyStart))
        }
        return BaseDictionaryIndex(keyUnits: keyUnits, keyStart: keyStart, valueOffset: valueOffset, valueData: dat.data)
    }

    /// Kho `entries` (từ điển nạp từ text, nhỏ): khoá theo thứ tự chữ, nghĩa chép vào pool tự dựng cùng khuôn `.dat`.
    private static func build(
        entries: [String: String],
        firstPageSize: Int,
        onFirstPage: ([String]) -> Void
    ) -> BaseDictionaryIndex {
        var keyUnits: [UInt16] = []
        var keyStart: [Int32] = [0]
        var valueOffset: [Int32] = []
        var pool = Data()
        for key in entries.keys.sorted() {
            keyUnits.append(contentsOf: key.utf16)
            keyStart.append(Int32(keyUnits.count))
            let bytes = Array((entries[key] ?? "").utf8.prefix(Int(UInt16.max)))
            valueOffset.append(Int32(pool.count))
            pool.append(UInt8(bytes.count >> 8))
            pool.append(UInt8(bytes.count & 0xFF))
            pool.append(contentsOf: bytes)
        }
        onFirstPage(firstKeys(keyUnits: keyUnits, keyStart: keyStart, limit: firstPageSize))
        return BaseDictionaryIndex(keyUnits: keyUnits, keyStart: keyStart, valueOffset: valueOffset, valueData: pool)
    }

    private static func firstKeys(keyUnits: [UInt16], keyStart: [Int32], limit: Int = .max) -> [String] {
        let count = min(keyStart.count - 1, limit)
        return (0..<max(0, count)).map {
            String(decoding: keyUnits[Int(keyStart[$0])..<Int(keyStart[$0 + 1])], as: UTF16.self)
        }
    }
}
