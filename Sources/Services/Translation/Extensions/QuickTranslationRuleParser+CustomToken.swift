import Foundation

/// Token tùy chọn `<@tên>` của DSL rule dịch (1.3.1063): khớp **một** từ trong danh sách của token người dùng tự tạo
/// (`QuickTranslationCustomTokenStore`), `{i}` = nghĩa của từ đó, từ dài thử trước.
///
/// **Parser không tra token có tồn tại hay không.** Lỗi `UNKNOWN_TOKEN_NAME` là lỗi nặng, và luồng ghi canonical
/// (`QuickTranslationRuleRecordStore.validRecords`) **bỏ** dòng có lỗi nặng ở lần ghi kế tiếp — nếu parse phụ thuộc token
/// đang có thì xoá token, tắt nó hay khôi phục Backup sai thứ tự sẽ âm thầm xoá luôn rule của người dùng. Vì vậy chỉ cú
/// pháp được kiểm ở đây; token vắng / tắt / trống là trạng thái lúc chạy: matcher không có ứng viên ⇒ rule không khớp,
/// màn Quản lý rule báo `DICT_TOKEN_WITHOUT_DICTIONARY` (`QuickTranslationRuleStore+CustomTokenIssues`).
///
/// Cú pháp: `@` + tên `a-z 0-9 _` (bắt đầu bằng chữ); viết HOA cả tên (`<@MAU>`) = ép viết hoa nghĩa như `<VP>`; `?` vẫn
/// dùng được. Không nhận `:min-max` (danh sách tự quyết độ dài) và không ghép `|` — muốn "hoặc" thì dùng nhóm
/// `(<@a>|<@b>)` (các nhánh dùng chung số `{i}`).
extension QuickTranslationRuleParser {
    /// `spec` là phần giữa `<` và `>`. `nil` khi `spec` không dính tới `@` để `parseToken` đi tiếp đường token thường.
    static func parseCustomToken(
        spec: String,
        isOptional: Bool,
        captureCount: inout Int
    ) throws -> QuickTranslationRuleElement? {
        guard spec.contains("@") else { return nil }
        guard !spec.contains("|") else {
            throw ParseError(code: .unknownTokenName, message: "Token tùy chọn <\(spec)> không ghép được bằng dấu |; dùng nhóm (<@a>|<@b>)")
        }
        guard !spec.contains(":") else {
            throw ParseError(code: .unknownTokenName, message: "Token tùy chọn <\(spec)> không nhận độ dài :min-max")
        }
        guard spec.hasPrefix("@"),
              let parsed = QuickTranslationCustomTokenListParser.ruleName(String(spec.dropFirst())) else {
            throw ParseError(code: .unknownTokenName, message: "Tên token tùy chọn <\(spec)> chỉ gồm a-z, 0-9, _ và bắt đầu bằng chữ")
        }

        let index = captureCount
        captureCount += 1
        return QuickTranslationRuleElement(
            kind: .dictionary([.custom]),
            sourceTokenKinds: [],
            minLength: 1,
            maxLength: QuickTranslationCustomTokenListParser.maxKeyUTF16Length,
            isOptional: isOptional,
            captureIndex: index,
            capitalizesMeaning: parsed.capitalizesMeaning,
            customTokenName: parsed.name
        )
    }

    /// Tên token tùy chọn (chữ thường, không `@`) nếu `spec` đúng là `<@tên>` / `<@TÊN>` — màn sửa rule hỏi để biết chip
    /// nào là token tùy chọn mà không cài lại luật tên.
    static func customTokenName(inSpec spec: String) -> String? {
        guard spec.hasPrefix("@") else { return nil }
        return QuickTranslationCustomTokenListParser.ruleName(String(spec.dropFirst()))?.name
    }
}
