import ContentBlockerConverter
import Foundation
import WebKit

/// Chuyển bộ lọc AdGuard (text) sang JSON luật WebKit bằng SafariConverterLib, rồi biên dịch/tra
/// `WKContentRuleList` trong `WKContentRuleListStore(url: adblock/compiled/)`.
///
/// - Chuyển đổi tốn CPU (Base ~57k dòng mất vài giây) ⇒ chạy ở `Task.detached(priority: .utility)`.
/// - API WebKit (`lookUp`/`compile`) gọi trên MainActor; completion của WebKit về main.
/// - Mỗi bộ một rule list riêng, định danh `adblock-<id>` — một bộ vượt trần luật không kéo bộ khác theo.
/// - Đợt 1 chỉ luật cơ bản (`advancedBlocking: false`): scriptlet / extended CSS bị bỏ qua.
///
/// File **duy nhất** import `ContentBlockerConverter` (thư viện có `Logger`, `DomainUtils`… public — giữ tên
/// của thư viện khỏi phần còn lại của app).
enum AdBlockRuleCompiler {
    /// Kết quả chuyển đổi — chép từ `ConversionResult` (không `Sendable`) sang struct riêng để trả qua task.
    struct Conversion: Sendable {
        let json: String
        let jsonChecksum: String
        let sourceRuleCount: Int
        let safariRuleCount: Int
        /// Luật bị bỏ vì vượt trần của WebKit (số luật / kích thước JSON).
        let discardedRuleCount: Int
        /// Luật nguồn không chuyển được.
        let errorsCount: Int
    }

    enum CompileError: LocalizedError {
        case storeUnavailable
        case noRuleList

        var errorDescription: String? {
            switch self {
            case .storeUnavailable: return "Không mở được kho luật WebKit"
            case .noRuleList: return "WebKit không trả về rule list"
            }
        }
    }

    /// Khoá phiên bản bộ chuyển đổi + Safari đích. Đổi (nâng thư viện / nâng iOS) ⇒ biên dịch lại dù nguồn
    /// không đổi. Nâng `exactVersion` của SafariConverterLib trong `project.yml` thì sửa số ở đây.
    static let compilerKey = "safari-converter-4.3.1|safari-\(SafariVersion.autodetect().description)"

    static func identifier(for filterId: Int) -> String {
        "adblock-\(filterId)"
    }

    // MARK: - Chuyển đổi (nền)

    static func convert(_ text: String) async -> Conversion {
        await Task.detached(priority: .utility) { () -> Conversion in
            var content = text
            content.makeContiguousUTF8()
            let lines = splitLines(content)
            let result = ContentBlockerConverter().convertArray(
                rules: lines,
                safariVersion: SafariVersion.autodetect(),
                advancedBlocking: false,
                maxJsonSizeBytes: nil,
                progress: nil
            )
            let json = result.safariRulesJSON
            return Conversion(
                json: json,
                jsonChecksum: json.sha256(),
                sourceRuleCount: result.sourceRulesCount,
                safariRuleCount: result.safariRulesCount,
                discardedRuleCount: result.discardedSafariRules,
                errorsCount: result.errorsCount
            )
        }.value
    }

    /// Tách theo byte `\n` và bỏ `\r` cuối dòng: file AdGuard trả về là CRLF, mà `"\r\n"` là **một** `Character`
    /// trong Swift nên `split(separator: "\n")` theo ký tự sẽ không tách được.
    private static func splitLines(_ content: String) -> [String] {
        var lines: [String] = []
        for var line in content.utf8.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if line.last == 0x0D { line = line.dropLast() }
            guard !line.isEmpty else { continue }
            lines.append(String(decoding: line, as: UTF8.self))
        }
        return lines
    }

    // MARK: - WebKit (main)

    @MainActor private static var cachedStore: WKContentRuleListStore?

    @MainActor
    private static func ruleListStore() -> WKContentRuleListStore? {
        if let cachedStore { return cachedStore }
        guard AdBlockPaths.ensureDirectory(AdBlockPaths.compiledDirectory) else { return nil }
        // Khai kiểu tường minh: header WebKit nhập `storeWithURL:` thành init không-optional.
        let store: WKContentRuleListStore = WKContentRuleListStore(url: AdBlockPaths.compiledDirectory)
        cachedStore = store
        return store
    }

    /// Rule list đã biên dịch từ trước (lượt chạy cũ); `nil` khi chưa có — không phải lỗi, không log `❌`.
    @MainActor
    static func lookUp(filterId: Int) async -> WKContentRuleList? {
        guard let store = ruleListStore() else { return nil }
        let ruleListId = identifier(for: filterId)
        return await withCheckedContinuation { (continuation: CheckedContinuation<WKContentRuleList?, Never>) in
            store.lookUpContentRuleList(forIdentifier: ruleListId) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }

    /// Biên dịch JSON luật vào store (ghi đè bản cùng định danh).
    @MainActor
    static func compile(filterId: Int, json: String) async throws -> WKContentRuleList {
        guard let store = ruleListStore() else { throw CompileError.storeUnavailable }
        let ruleListId = identifier(for: filterId)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WKContentRuleList, Error>) in
            store.compileContentRuleList(forIdentifier: ruleListId, encodedContentRuleList: json) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(throwing: error ?? CompileError.noRuleList)
                }
            }
        }
    }
}
