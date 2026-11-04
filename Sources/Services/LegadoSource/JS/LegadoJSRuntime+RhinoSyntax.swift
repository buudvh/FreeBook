import Foundation
import JavaScriptCore

/// Phân tích lại và sửa mã của nguồn khi JavaScriptCore báo lỗi cú pháp mà Rhino chấp nhận (spec §6.1, "Tương thích
/// Rhino"; phép sửa ở `LegadoJSRhinoSyntax`). Dùng cho rule JS lẫn `jsLib`.
extension LegadoJSRuntime {
    /// Số lần sửa tối đa cho một đoạn mã (mỗi lần một lỗi: bỏ ký tự Cf, hoặc đổi một `let` trùng tham số).
    private static let maxRhinoFixes = 6

    /// Bản sửa của `code`: phân tích bằng `JSCheckScriptSyntax` — **chỉ phân tích, không chạy** — sửa lỗi đầu, lặp tới khi
    /// hết lỗi hoặc gặp lỗi không sửa được. Không sửa được gì ⇒ `nil`.
    func rhinoCompatibleSource(_ code: String) -> String? {
        var current = code
        var changed = false
        for _ in 0..<Self.maxRhinoFixes {
            guard let issue = syntaxIssue(in: current),
                  let fixed = LegadoJSRhinoSyntax.fix(current, message: issue.message, line: issue.line) else { break }
            current = fixed
            changed = true
        }
        return changed ? current : nil
    }

    /// Lỗi cú pháp đầu tiên của `code` (không chạy): thông báo, dòng (từ 1; 0 = không có), đối tượng lỗi. Phân tích được
    /// ⇒ `nil`.
    func syntaxIssue(in code: String) -> (message: String, line: Int, error: JSValue)? {
        guard let script = JSStringCreateWithCFString(code as CFString) else { return nil }
        defer { JSStringRelease(script) }
        var exception: JSValueRef?
        guard !JSCheckScriptSyntax(context.jsGlobalContextRef, script, nil, 1, &exception), let exception,
              let error = JSValue(jsValueRef: exception, in: context) else { return nil }
        var line = 0
        if let value = error.objectForKeyedSubscript("line"), value.isNumber {
            line = Int(value.toInt32())
        }
        return (message: error.toString() ?? "", line: line, error: error)
    }
}
