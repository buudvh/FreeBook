import Foundation

/// Đánh dấu `<m>` có `{i}` **đứng đầu bản dịch** (`leadsReplacement`, 1.3.1094 — anh Bửu: "nếu giá trị thay thế đứng đầu
/// mới đọc là mười", rồi chọn "dùng chung" cho cả luật nhận chữ số).
///
/// Trước 1.3.1094 tiêu chí nằm ở **vế trái** (1.3.703: `<m>` là phần tử đầu của mẫu). Đổi sang vế phải vì vế phải nói đúng
/// vai của token hơn: `百分之<m>几 = {0} mấy phần trăm` có `<m>` đứng thứ hai trong mẫu nhưng `{0}` mở đầu bản dịch —
/// `百分之十几` phải là "mười mấy phần trăm", `百分之二十几` phải nhận được `二十`. Rule `几<m>年 = mấy {0} năm`, `数<m> =
/// mấy {0}` có chữ "mấy" trước `{0}` ⇒ chỉ bậc trần, `十` đọc mươi.
///
/// "Đầu bản dịch" = đoạn đầu tiên của `template` sau khi bỏ các đoạn chữ chỉ có khoảng trắng. Giới hạn đã biết (anh đã
/// nghe): rule có chữ trước `{0}` như `约<m>几年 = khoảng {0} mấy năm` thì `{0}` không đứng đầu ⇒ `约十几年` ra "khoảng mươi
/// mấy năm", `约二十几年` không khớp. Duyệt cả nhánh của nhóm (các nhánh dùng chung số `{i}`, 1.3.687).
///
/// Tách file riêng để `QuickTranslationRuleCompiler.swift` không vượt trần 400 dòng.
extension QuickTranslationRuleCompiler {
    static func markLeadingMagnitude(
        _ elements: inout [QuickTranslationRuleElement],
        template: [QuickTranslationCompiledRule.TemplateSegment]
    ) {
        guard let leadingCapture = leadingCaptureIndex(of: template) else { return }
        markMagnitude(&elements, capture: leadingCapture)
    }

    private static func leadingCaptureIndex(of template: [QuickTranslationCompiledRule.TemplateSegment]) -> Int? {
        for segment in template {
            switch segment {
            case .text(let text):
                if text.allSatisfy(\.isWhitespace) { continue }
                return nil
            case .capture(let index):
                return index
            }
        }
        return nil
    }

    private static func markMagnitude(_ elements: inout [QuickTranslationRuleElement], capture: Int) {
        for index in elements.indices {
            switch elements[index].kind {
            case .numeral(.magnitude):
                if elements[index].captureIndex == capture { elements[index].leadsReplacement = true }
            case .group(var alternatives):
                for branch in alternatives.indices {
                    markMagnitude(&alternatives[branch], capture: capture)
                }
                elements[index].kind = .group(alternatives)
            case .literal, .numeral, .chapterLabel, .dictionary, .anyRun, .lineStart, .lineEnd, .openBracket, .closeBracket:
                continue
            }
        }
    }
}
