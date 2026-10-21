import Foundation

/// Lỗi một hàm native ném ngược vào JS (thành `Error` JS mà script `try/catch` được).
struct LegadoJSNativeError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    /// Tiền tố thông báo của stub hàm hoãn — bộ nghiệm thu dựa vào đây để xếp loại "cú pháp chưa hỗ trợ".
    static let unsupportedPrefix = "Chưa hỗ trợ "

    static func unsupported(_ name: String) -> LegadoJSNativeError {
        LegadoJSNativeError("\(unsupportedPrefix)\(name) ở bản này")
    }
}
