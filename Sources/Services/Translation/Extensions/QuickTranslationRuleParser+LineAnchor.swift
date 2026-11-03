import Foundation

/// Neo dòng `<^>` / `<$>` của DSL rule dịch (1.3.686).
///
/// Neo là phần tử **rộng 0** và **không sinh capture**: `<^>第<n>章 = Chương {0}` vẫn gọi `<n>` là `{0}`.
/// Vì vậy parser phải nhận ra neo **trước** bước cấp số capture trong `parseToken`, và màn sửa rule
/// (`QuickTranslationRuleDraftAnalyzer.segments`) hỏi đúng `isLineAnchorSpec` để không đánh số chip neo.
///
/// Neo không có độ dài, không vắng mặt được và không ghép `|` với token khác: mỗi kiểu viết đó báo
/// `UNKNOWN_TOKEN_NAME` (lỗi nặng) kèm câu giải thích thay vì lặng lẽ bỏ phần thừa.
extension QuickTranslationRuleParser {
    /// `spec` là phần giữa `<` và `>` (vd `^`, `n:1-6`, `ne|pn`). `true` khi tên token có nhắc tới neo
    /// dòng — kể cả cách viết sai như `<^|n>` hay `<$:1-2>`, để hai nơi đếm token hiểu giống nhau.
    static func isLineAnchorSpec(_ spec: String) -> Bool {
        !lineAnchorNames(in: spec).anchors.isEmpty
    }

    /// Trả phần tử neo khi `spec` đúng là `^` hoặc `$`; ném lỗi khi neo bị viết kèm `|`, `:min-max`
    /// hoặc `?`; trả `nil` khi `spec` không dính tới neo để `parseToken` đi tiếp đường token thường.
    static func parseLineAnchor(spec: String, isOptional: Bool) throws -> QuickTranslationRuleElement? {
        let parsed = lineAnchorNames(in: spec)
        guard let kind = parsed.anchors.first else { return nil }

        guard parsed.names.count == 1 else {
            throw ParseError(code: .unknownTokenName, message: "Neo \(kind.syntax) không ghép được với token khác bằng dấu |")
        }
        guard !parsed.hasLength else {
            throw ParseError(code: .unknownTokenName, message: "Neo \(kind.syntax) không chiếm ký tự nào nên không nhận độ dài :min-max")
        }
        guard !isOptional else {
            throw ParseError(code: .unknownTokenName, message: "Neo \(kind.syntax) không dùng kèm dấu ? (vắng mặt) được")
        }

        let elementKind: QuickTranslationRuleElement.Kind = kind == .lineStart ? .lineStart : .lineEnd
        return QuickTranslationRuleElement(
            kind: elementKind,
            sourceTokenKinds: [kind],
            minLength: 0,
            maxLength: 0
        )
    }

    /// Tách `spec` đúng như `parseToken` (tên trước dấu `:`, ngăn bằng `|`, bỏ khoảng trắng hai đầu).
    private static func lineAnchorNames(
        in spec: String
    ) -> (names: [String], anchors: [QuickTranslationRuleTokenSettings.Kind], hasLength: Bool) {
        let parts = spec.components(separatedBy: ":")
        let names = parts[0].components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let anchors = names.compactMap { name -> QuickTranslationRuleTokenSettings.Kind? in
            guard let kind = QuickTranslationRuleTokenSettings.Kind(rawValue: name), kind.isLineAnchor else { return nil }
            return kind
        }
        return (names, anchors, parts.count > 1)
    }
}
