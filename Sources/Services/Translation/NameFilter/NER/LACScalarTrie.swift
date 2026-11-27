import Foundation

/// Cây tiền tố theo **Unicode scalar** cho từ điển của LAC (`small_seg.dic`, `word.dic`).
///
/// Khoá là dãy scalar (`UInt32`), không phải `String`: `String` của Swift so bằng tương đương chính tắc (vd chữ tương
/// thích CJK U+F900 "bằng" U+8C48), còn LAC (Python) so từng code point — dùng `String` làm khoá là lệch ngầm.
///
/// Một bảng băm phẳng `(nút << 21) | scalar → nút con` (scalar ≤ U+10FFFF vừa 21 bit) + mảng `payload` theo nút
/// (`-1` = chỉ là tiền tố). Nút gốc là 0. Bất biến sau khi dựng ⇒ đọc song song được.
struct LACScalarTrie: Sendable {
    static let root: Int32 = 0

    private var edges: [UInt64: Int32] = [:]
    private var payloads: [Int32] = [-1]
    private(set) var maxDepth = 0

    init(reservingCapacity capacity: Int = 0) {
        edges.reserveCapacity(capacity)
        payloads.reserveCapacity(capacity + 1)
    }

    /// Thêm một từ; từ đã có ⇒ ghi đè `payload` (đúng kiểu "dòng sau ghi đè" của dict Python).
    mutating func insert<C: Collection>(_ scalars: C, payload: Int32) where C.Element == UInt32 {
        var node = Self.root
        var depth = 0
        for scalar in scalars {
            let key = Self.key(node, scalar)
            if let child = edges[key] {
                node = child
            } else {
                let child = Int32(payloads.count)
                payloads.append(-1)
                edges[key] = child
                node = child
            }
            depth += 1
        }
        payloads[Int(node)] = payload
        maxDepth = max(maxDepth, depth)
    }

    /// Nút con theo một scalar, `nil` khi dãy hiện tại + scalar không phải từ cũng không phải tiền tố của từ nào.
    @inline(__always)
    func child(of node: Int32, _ scalar: UInt32) -> Int32? {
        edges[Self.key(node, scalar)]
    }

    /// `payload` của nút (`-1` = không phải từ).
    @inline(__always)
    func payload(of node: Int32) -> Int32 {
        payloads[Int(node)]
    }

    /// `payload` của đúng dãy này, `nil` khi dãy không phải một từ.
    func lookup<C: Collection>(_ scalars: C) -> Int32? where C.Element == UInt32 {
        var node = Self.root
        for scalar in scalars {
            guard let next = child(of: node, scalar) else { return nil }
            node = next
        }
        let value = payloads[Int(node)]
        return value >= 0 ? value : nil
    }

    @inline(__always)
    private static func key(_ node: Int32, _ scalar: UInt32) -> UInt64 {
        (UInt64(UInt32(bitPattern: node)) << 21) | UInt64(scalar & 0x1F_FFFF)
    }
}
