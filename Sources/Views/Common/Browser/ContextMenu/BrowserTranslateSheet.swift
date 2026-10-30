import SwiftUI
import UIKit

/// Sheet "Dịch QT" của menu bôi đen trong trình duyệt (mockup "Mới 6"): bản gốc, bản dịch QT (dịch ngoài main bằng từ
/// điển chung — trình duyệt không gắn truyện), nút "Sao chép bản dịch" và "Tra từ điển" (mở sheet Tra từ điển cho
/// token có chữ Hán đầu tiên). Sheet nhỏ, vuốt xuống để đóng, không nút đóng.
struct BrowserTranslateSheet: View {
    let source: String

    @State private var translated: String?
    @State private var lookupRequest: BrowserLookupRequest?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Bản gốc") {
                        Text(source)
                            .font(.system(size: 14.5))
                            .foregroundStyle(.secondary)
                    }
                    section("Bản dịch") {
                        if let translated {
                            Text(translated)
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    HStack(spacing: 8) {
                        BrowserCapsuleButton(title: "Sao chép bản dịch", action: { copyTranslation() }) {
                            AppGlyph.copy.image(size: 15)
                        }
                        .disabled(translated == nil)
                        BrowserCapsuleButton(title: "Tra từ điển", action: { openLookup() }) {
                            Image(systemName: "book")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .pageTitle("Dịch QT")
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task { await translate() }
        .sheet(item: $lookupRequest) { request in
            BrowserDictionarySheet(request: request)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
            content()
                .textSelection(.enabled)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func translate() async {
        let text = source
        let result = await Task.detached(priority: .userInitiated) {
            TranslateUtils.translateContent(text, bookId: nil)
        }.value
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        translated = trimmed.isEmpty ? source : result
    }

    private func copyTranslation() {
        guard let translated else { return }
        UIPasteboard.general.string = translated
        ToastManager.shared.show(message: "Đã sao chép bản dịch", type: .success)
    }

    private func openLookup() {
        lookupRequest = BrowserLookupRequest(context: source)
    }
}
