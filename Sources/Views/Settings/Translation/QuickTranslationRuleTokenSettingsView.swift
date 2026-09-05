import SwiftUI

/// Công tắc runtime cho các token DSL của Quick Translate.
///
/// Các công tắc này không sửa file rule. Khi một token bị tắt, engine chỉ bỏ qua những rule có ghi
/// đúng token đó trong cú pháp gốc; rule không liên quan vẫn được nạp và hiển thị bình thường.
struct QuickTranslationRuleTokenSettingsView: View {
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.numeral.userDefaultsKey) private var isNumeralEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.digitwise.userDefaultsKey) private var isDigitwiseEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.hanDigits.userDefaultsKey) private var isHanDigitsEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.asciiDigits.userDefaultsKey) private var isAsciiDigitsEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.chapterLabel.userDefaultsKey) private var isChapterLabelEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.name.userDefaultsKey) private var isNameEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.pronoun.userDefaultsKey) private var isPronounEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.vietPhrase.userDefaultsKey) private var isVietPhraseEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.hanViet.userDefaultsKey) private var isHanVietEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.word.userDefaultsKey) private var isWordEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.magnitude.userDefaultsKey) private var isMagnitudeEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.latinLetters.userDefaultsKey) private var isLatinLettersEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle(QuickTranslationRuleTokenSettings.Kind.numeral.label, isOn: invalidating($isNumeralEnabled))
                Toggle(QuickTranslationRuleTokenSettings.Kind.digitwise.label, isOn: invalidating($isDigitwiseEnabled))
                Toggle(QuickTranslationRuleTokenSettings.Kind.hanDigits.label, isOn: invalidating($isHanDigitsEnabled))
                Toggle(QuickTranslationRuleTokenSettings.Kind.asciiDigits.label, isOn: invalidating($isAsciiDigitsEnabled))
                Toggle(QuickTranslationRuleTokenSettings.Kind.magnitude.label, isOn: invalidating($isMagnitudeEnabled))
                Toggle(QuickTranslationRuleTokenSettings.Kind.latinLetters.label, isOn: invalidating($isLatinLettersEnabled))
                Toggle(QuickTranslationRuleTokenSettings.Kind.chapterLabel.label, isOn: invalidating($isChapterLabelEnabled))
            } header: {
                Text("Token lớp ký tự và nhãn")
            } footer: {
                Text("<m> khớp đúng một ký tự bậc Hán và trả về số: 十 → 10, 百 → 100, 千 → 1000. Viết 几<m>年 = mấy {0} năm là một rule phủ cả mấy mươi / mấy trăm / mấy nghìn năm.\n\n<a> khớp chuỗi chữ cái A-Z và trả nguyên văn, giữ đúng hoa/thường: <a>级 = cấp {0} phủ A级, BB级, SSS级.")
            }

            Section {
                Toggle(QuickTranslationRuleTokenSettings.Kind.name.label, isOn: invalidating($isNameEnabled))
                Toggle(QuickTranslationRuleTokenSettings.Kind.pronoun.label, isOn: invalidating($isPronounEnabled))
                Toggle(QuickTranslationRuleTokenSettings.Kind.vietPhrase.label, isOn: invalidating($isVietPhraseEnabled))
                Toggle(QuickTranslationRuleTokenSettings.Kind.hanViet.label, isOn: invalidating($isHanVietEnabled))
                Toggle(QuickTranslationRuleTokenSettings.Kind.word.label, isOn: invalidating($isWordEnabled))
            } header: {
                Text("Token từ điển")
            } footer: {
                Text("<w> có công tắc riêng, không phụ thuộc <ne>, <pn> hay <vp>.")
            }

            Section {
                Text("Tắt token chỉ tạm vô hiệu toàn bộ rule có chứa đúng token đó, kể cả token trong nhóm, danh sách | hoặc phần tùy chọn. File QuickTranslateRules.txt không bị sửa.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Cấu hình token rule")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Mỗi thay đổi hợp lệ làm cache dịch mất hiệu lực và phát đúng một tín hiệu cập nhật UI.
    private func invalidating(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in
                guard binding.wrappedValue != value else { return }
                binding.wrappedValue = value
                TranslateUtils.clearCache()
                TranslationManager.shared.notifyDictionariesDidUpdate()
            }
        )
    }
}
