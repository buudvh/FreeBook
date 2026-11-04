import Foundation

/// Đánh dấu `<m>` **đứng đầu mẫu** (1.3.703) để `十`/`一十` đọc `mười` thay vì `mươi`.
///
/// `<m>` vốn ra chữ đơn vị để ghép sau số đếm: `几<m>年 = mấy {0} năm` trên `几十年` ⇒ `mấy mươi năm`. Nhưng khi `<m>` là
/// phần tử đầu tiên của mẫu (`<m>几 = {0} mấy` trên `十几`), `十` là chính số 10 ⇒ `mười mấy`. Tiêu chí theo **vị trí trong
/// mẫu** (người dùng chọn): neo `<START>`/`<END>` không chiếm ký tự nên bỏ qua; mẫu mở đầu bằng nhóm thì xét phần tử đầu
/// của từng nhánh; chữ cố định hay ngoặc đứng trước thì `<m>` không còn đứng đầu. Chỉ số 10 đổi cách đọc
/// (`QuickTranslationMagnitudeFormatter.renderMagnitude`).
///
/// Tách file riêng để `QuickTranslationRuleCompiler.swift` không vượt trần 400 dòng.
extension QuickTranslationRuleCompiler {
    static func markLeadingMagnitude(_ elements: inout [QuickTranslationRuleElement]) {
        guard let index = elements.firstIndex(where: { !$0.isLineAnchor }) else { return }
        switch elements[index].kind {
        case .numeral(.magnitude):
            elements[index].leadsPattern = true
        case .group(var alternatives):
            for branch in alternatives.indices {
                markLeadingMagnitude(&alternatives[branch])
            }
            elements[index].kind = .group(alternatives)
        case .literal, .numeral, .chapterLabel, .dictionary, .anyRun, .lineStart, .lineEnd, .openBracket, .closeBracket:
            return
        }
    }
}
