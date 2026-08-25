import SwiftUI

/// Công tắc runtime cho các token DSL của Quick Translate.
///
/// Các công tắc này không sửa file rule. Khi một token bị tắt, engine chỉ bỏ qua những rule có ghi
/// đúng token đó trong cú pháp gốc; rule không liên quan vẫn được nạp và hiển thị bình thường.
struct QuickTranslationRuleTokenSettingsView: View {
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.numeral.userDefaultsKey) private var isNumeralEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.digitwise.userDefaultsKey) private var isDigitwiseEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.chapterLabel.userDefaultsKey) private var isChapterLabelEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.name.userDefaultsKey) private var isNameEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.pronoun.userDefaultsKey) private var isPronounEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.vietPhrase.userDefaultsKey) private var isVietPhraseEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.hanViet.userDefaultsKey) private var isHanVietEnabled = true
    @AppStorage(QuickTranslationRuleTokenSettings.Kind.word.userDefaultsKey) private var isWordEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("<n> — số", isOn: invalidating($isNumeralEnabled))
                Toggle("<y> — đọc từng chữ số", isOn: invalidating($isDigitwiseEnabled))
                Toggle("<L> — nhãn chương", isOn: invalidating($isChapterLabelEnabled))
            } header: {
                Text("Token số và nhãn")
            } footer: {
                Text("Các token số và nhãn vẫn giữ nguyên cú pháp rule hiện có.")
            }

            Section {
                Toggle("<ne> — tên riêng", isOn: invalidating($isNameEnabled))
                Toggle("<pn> — đại từ", isOn: invalidating($isPronounEnabled))
                Toggle("<vp> — VietPhrase", isOn: invalidating($isVietPhraseEnabled))
                Toggle("<hv> — một chữ Hán-Việt", isOn: invalidating($isHanVietEnabled))
                Toggle("<w> — cụm từ điển", isOn: invalidating($isWordEnabled))
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
