import SwiftUI

/// Mục **NGÔN NGỮ** của popup dịch (`TranslationScopePopupView`): hai ô [Dịch từ ⇅] → [Dịch sang ⇅] theo danh sách của
/// `language.js` (`TranslationExtensionCatalog`), dòng phụ "<model> · <kiểu dịch>" của tiện ích.
///
/// - QT ⇒ hai ô mờ, không bấm được, dòng phụ "QT chỉ dịch Trung → Việt".
/// - Đang đọc danh sách ⇒ vòng xoay nhỏ; đọc lỗi ⇒ một dòng chữ đỏ + "Thử lại" (đọc lại danh sách). Hai trạng thái
///   này popup khoá "Lưu lại": tiện ích vừa chọn chưa có cặp ngôn ngữ của nó.
/// - Mã đã lưu không còn trong danh sách (tiện ích vừa cập nhật) vẫn hiện tên theo mã
///   (`TranslationLanguageOption.displayName(forCode:)`; `""` = "Tự nhận").
///
/// Caller ẩn cả mục khi bộ dịch là "Theo cấp trên".
struct TranslationLanguagePickerRow: View {
    enum Content {
        case quickTranslator
        case loading
        case failed(String)
        case loaded(TranslationExtensionCatalog.Options)
    }

    let content: Content
    @Binding var from: String
    @Binding var to: String
    /// Tiện ích đang chọn — đọc model / kiểu dịch đã chọn cho dòng phụ; `nil` với QT.
    let packageId: String?
    /// "Thử lại" khi đọc danh sách lỗi.
    let onRetryLoading: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NGÔN NGỮ")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            switch content {
            case .quickTranslator:
                HStack(spacing: 6) {
                    box(title: TranslationLanguageOption.displayName(forCode: "zh"))
                    arrow
                    box(title: TranslationLanguageOption.displayName(forCode: "vi"))
                }
                .opacity(0.45)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("QT dịch Trung sang Việt")
                detailLine("QT chỉ dịch Trung → Việt")
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Đang đọc danh sách ngôn ngữ…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            case .failed(let message):
                HStack(spacing: 8) {
                    Text(verbatim: "Lỗi đọc ngôn ngữ: \(message)")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(action: onRetryLoading) {
                        Text("Thử lại")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 34)
            case .loaded(let options):
                HStack(spacing: 6) {
                    languageMenu(options.sourceLanguages, selection: $from, label: "Dịch từ")
                    arrow
                    languageMenu(options.targetLanguages, selection: $to, label: "Dịch sang")
                }
                if let text = settingsText(options: options), !text.isEmpty {
                    detailLine(text)
                }
            }
        }
    }

    // MARK: - Mảnh

    private func languageMenu(
        _ languages: [TranslationLanguageOption],
        selection: Binding<String>,
        label: String
    ) -> some View {
        let currentName = Self.name(of: selection.wrappedValue, in: languages)
        return Menu {
            ForEach(languages) { language in
                Button {
                    selection.wrappedValue = language.id
                } label: {
                    HStack {
                        Text(language.name)
                        if language.id == selection.wrappedValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            box(title: currentName)
        }
        .disabled(languages.isEmpty)
        .accessibilityLabel("\(label): \(currentName)")
    }

    private func box(title: String) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
    }

    private func detailLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .lineLimit(1)
    }

    /// "<model> · <kiểu dịch>" đã chọn cho tiện ích (màn Cấu hình tiện ích); `""` = mặc định của tiện ích ⇒ bỏ phần đó.
    private func settingsText(options: TranslationExtensionCatalog.Options) -> String? {
        guard let packageId else { return nil }
        let settings = TranslationExtensionSettingsStore.shared
        let modelId = settings.model(packageId: packageId)
        let styleId = settings.style(packageId: packageId)
        let parts = [
            modelId.isEmpty ? nil : (options.models.first { $0.id == modelId }?.name ?? modelId),
            styleId.isEmpty ? nil : (options.styles.first { $0.id == styleId }?.name ?? styleId)
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Tên của mã trong danh sách; không có thì tên theo mã (`""` = "Tự nhận").
    private static func name(of code: String, in languages: [TranslationLanguageOption]) -> String {
        languages.first { $0.id == code }?.name ?? TranslationLanguageOption.displayName(forCode: code)
    }
}
