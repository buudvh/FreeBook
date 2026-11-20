import Foundation

/// Duyệt **toàn bộ** entry của kho mà không dựng mảng cặp khoá–nghĩa: nền của `allEntries()` (nhập / gộp từ điển — số mục
/// phải khớp `wordCount`, đừng đổi phép duyệt này). Danh sách từ điển gốc dùng chỉ mục riêng `BaseDictionaryIndex`
/// (1.3.1037, chép cùng phép tính) thay cho `allKeys()` cũ.
///
/// Với kho `.dat`: cạnh `state → next` tồn tại khi `next = base[state] + code` và `check[next] == state`; nút kết thúc của
/// `next` là `base[next]` khi `check[base[next]] == next` và `base[base[next]] >= 0`, nghĩa nằm ở `poolOffset + base[base[next]]`
/// (2 byte độ dài big-endian + UTF-8) — đúng phép tính của `trieMatches`. Chỉ mục con dựng **một lượt** (gom slot theo
/// `check[slot] > 0`, theo thứ tự slot tăng ⇒ con theo mã nén tăng). Duyệt sâu **tiền thứ tự** với ngăn xếp chỉ giữ
/// đường đi hiện tại (bộ nhớ O(độ sâu), không giữ mảng mọi nút như bản cũ của `allEntries`): khoá cha ra trước khoá
/// con, anh em theo mã nén tăng. Entry có nghĩa không giải mã được (UTF-8 hỏng) bị bỏ như ở `trieMatches`.
extension FrozenTrieDictionary {
    /// Gọi `body(khoá, nghĩa)` cho từng entry; `decodeValues == false` ⇒ `nghĩa` luôn `nil` (chỉ kiểm nghĩa giải mã được).
    /// `body` trả `false` ⇒ dừng ngay.
    func walkEntries(decodeValues: Bool, _ body: (String, String?) -> Bool) {
        guard let dat else {
            for (key, value) in entries {
                if !body(key, decodeValues ? value : nil) { return }
            }
            return
        }
        guard dat.check.count > 1 else { return }

        let slotCount = dat.check.count
        var childCount = [Int32](repeating: 0, count: slotCount)
        var totalChildren = 0
        for slot in 0..<slotCount where dat.check[slot] > 0 {
            childCount[Int(dat.check[slot])] += 1
            totalChildren += 1
        }
        var childOffset = [Int32](repeating: 0, count: slotCount + 1)
        var running = 0
        for state in 0..<slotCount {
            childOffset[state] = Int32(running)
            running += Int(childCount[state])
        }
        childOffset[slotCount] = Int32(running)
        var childSlots = [Int32](repeating: 0, count: totalChildren)
        // `childCount` hết việc ⇒ dùng lại làm con trỏ điền (mảng `base`/`check` thật tới hàng triệu slot).
        for state in 0..<slotCount { childCount[state] = childOffset[state] }
        for slot in 0..<slotCount where dat.check[slot] > 0 {
            let parent = Int(dat.check[slot])
            childSlots[Int(childCount[parent])] = Int32(slot)
            childCount[parent] += 1
        }

        // Đảo `fastCharMap`: lúc tra chỉ cần mã điểm → mã nén, duyệt cây cần chiều ngược lại.
        let maxCode = Int(dat.charMap.max() ?? 0)
        var unitByCode = [Int32](repeating: -1, count: maxCode + 1)
        for codePoint in 0..<dat.charMap.count where dat.charMap[codePoint] != 0 {
            unitByCode[Int(dat.charMap[codePoint])] = Int32(codePoint)
        }

        var path: [UInt16] = []
        // Mỗi khung: trạng thái + chỉ số con kế tiếp. Khung gốc (trạng thái 1) không ứng với ký tự nào; mọi khung khác ứng
        // với đúng một đơn vị cuối của `path`.
        var stack: [(state: Int, cursor: Int)] = [(1, Int(childOffset[1]))]
        while let top = stack.last {
            if top.cursor >= Int(childOffset[top.state + 1]) {
                stack.removeLast()
                if !stack.isEmpty { path.removeLast() }
                continue
            }
            stack[stack.count - 1].cursor += 1
            let next = Int(childSlots[top.cursor])
            let code = next - Int(dat.base[top.state])
            guard code >= 0, code < unitByCode.count, unitByCode[code] >= 0 else { continue }
            path.append(UInt16(unitByCode[code]))

            let terminal = Int(dat.base[next])
            if dat.base.indices.contains(terminal), dat.check[terminal] == Int32(next), dat.base[terminal] >= 0 {
                let offset = dat.poolOffset + Int(dat.base[terminal])
                if decodeValues {
                    if let range = Self.poolValueRange(at: offset, dat: dat),
                       let value = String(bytes: dat.data[range], encoding: .utf8),
                       !body(String(decoding: path, as: UTF16.self), value) {
                        return
                    }
                } else if Self.poolValueIsDecodable(at: offset, dat: dat),
                          !body(String(decoding: path, as: UTF16.self), nil) {
                    return
                }
            }
            stack.append((next, Int(childOffset[next])))
        }
    }
}
