import Foundation
import JavaScriptCore

/// `load('x.js')` của tiện ích.
///
/// Hợp đồng chuẩn (`extension-api.md`) định nghĩa `load('x.js')` là **thay văn bản trước khi chạy**: dòng đó được
/// thay bằng nội dung file, nên mọi khai báo của script chính đứng **sau** file nạp và thắng khi trùng tên. Nếu chỉ
/// chạy file nạp lúc gặp lời gọi, `function execute()` của script chính (đã hoist từ trước) bị `function execute()`
/// của file nạp đè ⇒ app gọi nhầm hàm của file nạp (vd. `config.js` có `execute()` riêng để thử cấu hình).
///
/// Cách làm thay cho thay văn bản (giữ nguyên số dòng của script chính cho màn Debug):
/// - `prepareScript` gọi `preloadEntryLibraries(of:)`: chạy trước các file mà script chính `load(...)` ở **đầu dòng**
///   (cột 0 — vị trí hợp đồng khuyên dùng), rồi mới chạy script chính.
/// - Mọi file chạy trong lúc chuẩn bị script chính được ghi vào `preparedLibraries`; lời gọi `load` cùng tên sau đó
///   (của chính script chính, hay lúc runtime) là no-op ⇒ không chạy lại file có `let` cấp cao nhất (SyntaxError trùng
///   khai báo) và không đè lại khai báo của script chính.
/// - `load` lúc runtime với file **chưa** nạp khi chuẩn bị (`Script.execute("gen.js", "execute")`, `Qt.include`, lời
///   gọi thụt lề trong thân hàm) giữ hành vi cũ: chạy file ngay, mỗi lần gọi.
extension JSExecutor {
    /// `load('x.js')` / `load("x.js")` ở cột 0 (cho phép BOM ở đầu file). Dòng `// load(...)` không khớp.
    private static let entryLoadRegex = try? NSRegularExpression(
        pattern: #"^\x{FEFF}?load\(\s*(['"])([^'"\r\n]+)\1\s*\)"#,
        options: [.anchorsMatchLines]
    )

    /// Đăng ký hàm toàn cục `load(filename)`: tìm file ở gốc tiện ích rồi tới `src/`, thiếu file ⇒ bỏ qua.
    internal func installLoadFunction() {
        let loadBlock: @convention(block) (String) -> Void = { [weak self] filename in
            self?.evaluateLibrary(named: filename)
        }
        context.setObject(loadBlock, forKeyedSubscript: "load" as NSCopying & NSObjectProtocol)
    }

    /// Chạy trước các file mà `scriptContent` nạp ở đầu dòng, theo thứ tự xuất hiện. Gọi trong lúc `isPreparingEntryScript`.
    internal func preloadEntryLibraries(of scriptContent: String) {
        guard let regex = Self.entryLoadRegex else { return }
        let text = scriptContent as NSString
        for match in regex.matches(in: scriptContent, range: NSRange(location: 0, length: text.length)) {
            evaluateLibrary(named: text.substring(with: match.range(at: 2)))
        }
    }

    private func evaluateLibrary(named filename: String) {
        guard !preparedLibraries.contains(filename), let localPath else { return }

        let extUrl = URL(fileURLWithPath: localPath)
        var fileUrl = extUrl.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: fileUrl.path) {
            fileUrl = extUrl.appendingPathComponent("src").appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: fileUrl.path) else { return }
        }
        guard let data = try? Data(contentsOf: fileUrl) else { return }

        // Ghi trước khi chạy: file nạp tự `load` lại chính nó cũng không lặp.
        if isPreparingEntryScript { preparedLibraries.insert(filename) }
        context.evaluateScript(decodeData(data))
    }
}
