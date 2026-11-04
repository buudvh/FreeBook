import Foundation

/// Neo dòng `<START>` / `<END>` của DSL rule dịch (1.3.686; trước 1.3.692 viết `<^>` / `<$>` — cách viết cũ
/// vẫn được nhận qua `QuickTranslationRuleTokenSettings.Kind.kind(forTokenName:)`).
///
/// Neo là phần tử **rộng 0** và **không sinh capture**: `<START>第<n>章 = Chương {0}` vẫn gọi `<n>` là `{0}`.
/// Vì vậy parser phải nhận ra neo **trước** bước cấp số capture trong `parseToken` (qua
/// `parseUncapturedToken`), và màn sửa rule hỏi `isUncapturedTokenSpec` để không đánh số chip neo/ngoặc.
///
/// Neo không có độ dài, không vắng mặt được và không ghép `|` với token khác: mỗi kiểu viết đó báo
/// `UNKNOWN_TOKEN_NAME` (lỗi nặng) kèm câu giải thích thay vì lặng lẽ bỏ phần thừa.
extension QuickTranslationRuleParser {
    /// `spec` là phần giữa `<` và `>` (vd `START`, `^`, `n:1-6`, `ne|pn`). `true` khi tên token có nhắc tới
    /// neo dòng — kể cả cách viết sai như `<START|n>` hay `<END:1-2>`. Giữ cho tương thích; màn sửa rule
    /// dùng `isUncapturedTokenSpec` (neo + ngoặc).
    static func isLineAnchorSpec(_ spec: String) -> Bool {
        !lineAnchorNames(in: spec).anchors.isEmpty
    }

    /// Trả phần tử neo khi `spec` đúng là `START`/`END` (hoặc `^`/`$`); ném lỗi khi neo bị viết kèm `|`, `:min-max`
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

    /// Tách `spec` đúng như `parseToken` (`tokenSpecNames`) rồi lọc ra các tên là neo dòng, kể cả tên cũ.
    private static func lineAnchorNames(
        in spec: String
    ) -> (names: [String], anchors: [QuickTranslationRuleTokenSettings.Kind], hasLength: Bool) {
        let parsed = tokenSpecNames(spec)
        let anchors = parsed.names.compactMap { name -> QuickTranslationRuleTokenSettings.Kind? in
            guard let kind = QuickTranslationRuleTokenSettings.Kind.kind(forTokenName: name), kind.isLineAnchor else {
                return nil
            }
            return kind
        }
        return (parsed.names, anchors, parsed.hasLength)
    }
}
