import Foundation

/// Phía native của script `concurrent` (spec §6.9): `java.lang.System.nanoTime()` và ô `AtomicLong` dùng chung toàn tiến
/// trình (`LegadoJavaSharedCells`). `parkNanos` đi qua lệnh `sleep` sẵn có (giới hạn 5 giây, huỷ được).
extension LegadoJSRuntime {
    func nativeConcurrent(_ command: String, _ arguments: LegadoJSArguments) throws -> String? {
        switch command {
        case "nanoTime":
            // Đồng hồ đơn điệu, chung mọi ngữ cảnh: ô giới hạn nhịp lưu mốc `nanoTime` của ngữ cảnh khác.
            return String(DispatchTime.now().uptimeNanoseconds)
        case "javaCell":
            return try javaCell(arguments)
        default:
            return nil
        }
    }

    /// `javaCell(lệnh, khoá, …)`. Giá trị trả về là chuỗi số; `""` = ô không có (hoặc bảng đầy khi `bind`).
    private func javaCell(_ arguments: LegadoJSArguments) throws -> String {
        guard let operation = arguments.plainString(0), let key = arguments.plainString(1) else {
            throw LegadoJSNativeError("javaCell: thiếu lệnh hoặc khoá")
        }
        let cells = LegadoJavaSharedCells.shared
        let value = arguments.number(2) ?? 0
        switch operation {
        case "peek", "get":
            return cells.value(key).map(Self.cellText) ?? ""
        case "bind":
            return cells.bind(key, value, replace: arguments.bool(3)).map(Self.cellText) ?? ""
        case "set":
            cells.set(key, value)
            return ""
        case "cas":
            return cells.compareAndSet(key, expect: value, update: arguments.number(3) ?? 0) ? "1" : "0"
        case "add":
            let result = cells.add(key, value)
            return "[" + Self.cellText(result.old) + "," + Self.cellText(result.new) + "]"
        case "swap":
            return Self.cellText(cells.swap(key, value))
        default:
            throw LegadoJSNativeError("javaCell: lệnh lạ \(operation)")
        }
    }

    /// Số nguyên in không kèm `.0`; số thực in dạng khứ hồi chính xác của `Double` (JS đọc lại bằng `Number`/`JSON.parse`).
    private static func cellText(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 9.0e15 { return String(Int64(value)) }
        return String(value)
    }
}
