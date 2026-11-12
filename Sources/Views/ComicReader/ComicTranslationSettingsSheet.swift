import SwiftUI

/// Sheet **Cài đặt dịch** của màn đọc truyện tranh (1.3.833, ngăn kéo `⋯`), bám mục "Dịch thuật Quick Translate" của
/// `ReaderSettingsView`:
/// - Dịch · Truyện này: Theo nguồn / Bật / Tắt — Nguồn: Toàn cục / Bật / Tắt — Mặc định toàn cục. Cùng kho với truyện chữ và
///   trang Chi tiết (`TranslationConfigStore`), một công tắc cho cả tên chương lẫn dịch ảnh.
/// - Khi đang bật: dịch đại từ / luật nhân hoá (cài đặt
///   chung của app, cùng khoá `@AppStorage` với Reader), thứ tự ưu tiên rule + token rule của truyện (mở lại hai màn của
///   Reader).
///
/// Chọn là ghi ngay; kho bắn thông báo nên màn đọc dịch lại (đại từ / luật nhân hoá đi qua
/// `TranslationManager.notifyDictionariesDidUpdate` như Reader). Không sửa `ReaderSettingsView` (lặp vài picker là chủ ý).
/// Không có nút chỉ để đóng: vuốt xuống.
struct ComicTranslationSettingsSheet: View {
    typealias ScopeOverride = TranslationConfigStore.ScopeOverride

    let bookId: String
    let packageId: String
    let sourceName: String
    let isChineseSourceHint: Bool?

    @AppStorage("isTranslationPronounsEnabled") private var isPronounsEnabled = false
    @AppStorage("isTranslationLuatNhanEnabled") private var isLuatNhanEnabled = false
    @State private var bookOverride: ScopeOverride
    @State private var sourceOverride: ScopeOverride
    @State private var globalEnabled: Bool
    @State private var isEnabled: Bool
    @State private var showsRulePriority = false
    @State private var showsTokenSettings = false

    /// Đọc trạng thái lưu ngay trong `init` (không trong `onAppear`): gán `@State` lúc hiện sẽ kích `onChange` ⇒ ghi lại cùng
    /// giá trị và bắn thông báo đổi cấu hình thừa (như `MediaCaptionTranslationSheet`).
    init(bookId: String, packageId: String, sourceName: String, isChineseSourceHint: Bool?) {
        self.bookId = bookId
        self.packageId = packageId
        self.sourceName = sourceName
        self.isChineseSourceHint = isChineseSourceHint
        let store = TranslationConfigStore.shared
        _bookOverride = State(initialValue: store.getBookOverride(bookId: bookId))
        _sourceOverride = State(initialValue: store.getSourceOverride(packageId: packageId))
        _globalEnabled = State(initialValue: store.globalEnabled)
        _isEnabled = State(initialValue: store.isTranslationEnabled(
            bookId: bookId,
            packageId: packageId,
            isChineseSourceHint: isChineseSourceHint
        ))
    }

    private var store: TranslationConfigStore { .shared }

    private var sourceLabel: String { sourceName.isEmpty ? "Nguồn" : "Nguồn (\(sourceName))" }

    var body: some View {
        NavigationStack {
            Form { Group {
                scopeSection
                if isEnabled {
                    methodSection
                }
            }.glassSheetRows() }
            .pageTitle("Cài đặt dịch")
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showsRulePriority) {
            NavigationStack { ReaderBookRulePriorityView(bookId: bookId) }
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsTokenSettings) {
            NavigationStack { ReaderBookTokenSettingsView(bookId: bookId) }
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Mục

    private var scopeSection: some View {
        Section {
            HStack {
                Text("Hiện tại")
                Spacer()
                Text(isEnabled ? "Đang bật" : "Đang tắt")
                    .fontWeight(.semibold)
                    .foregroundStyle(isEnabled ? Color.green : Color.secondary)
            }
            scopePicker("Truyện này", selection: $bookOverride, inheritedTitle: "Theo nguồn")
                .onChange(of: bookOverride) { _, mode in
                    store.setBookOverride(bookId: bookId, mode: mode)
                    refresh()
                }
            scopePicker(sourceLabel, selection: $sourceOverride, inheritedTitle: "Toàn cục")
                .onChange(of: sourceOverride) { _, mode in
                    store.setSourceOverride(packageId: packageId, mode: mode)
                    refresh()
                }
            Toggle("Mặc định toàn cục (tất cả truyện)", isOn: $globalEnabled)
                .onChange(of: globalEnabled) { _, enabled in
                    store.globalEnabled = enabled
                    refresh()
                }
        } header: {
            SectionHelpHeader("Dịch Quick Translate", texts: [
                Text("Một công tắc cho cả tên chương lẫn chữ trên ảnh — cùng công tắc với nút dịch ở trang Chi tiết và trên thanh trên của màn đọc."),
                Text("Thứ tự: truyện này > nguồn > nguồn tự khai tiếng Trung > toàn cục. Nguồn để \"Toàn cục\" mà không khai tiếng Trung thì mặc định không dịch; truyện tranh nhập từ file theo công tắc Mặc định toàn cục.")
            ])
        }
    }

    private var methodSection: some View {
        Section {
            Toggle("Dịch đại từ (Pronouns)", isOn: $isPronounsEnabled)
                .onChange(of: isPronounsEnabled) { _, _ in notifyEngineSettingChanged() }
            Toggle("Dịch luật nhân hoá", isOn: $isLuatNhanEnabled)
                .onChange(of: isLuatNhanEnabled) { _, _ in notifyEngineSettingChanged() }
            ruleRow(
                title: "Thứ tự ưu tiên rule",
                detail: QuickTranslationBookEngineConfigStore.shared.hasPriorityOverride(bookId: bookId)
                    ? "Đang đặt riêng cho truyện này"
                    : "Đang theo cài đặt chung",
                systemImage: "arrow.up.arrow.down"
            ) {
                showsRulePriority = true
            }
            ruleRow(title: "Token rule của truyện", detail: tokenRuleDetail, systemImage: "switch.2") {
                showsTokenSettings = true
            }
        } header: {
            SectionHelpHeader("Cách dịch", texts: [
                Text("Thứ tự ưu tiên rule và token rule chỉ áp cho truyện này. Phồn → giản nằm ở nút dịch trên thanh trên (theo phạm vi Truyện / Nguồn / Tất cả)."),
                Text("Dịch đại từ và luật nhân hoá là cài đặt chung của cả app, như ở Cài đặt trình đọc.")
            ])
        }
    }

    /// Cùng cách ghi của `ReaderSettingsView.ruleEngineOptions`: số token đặt riêng + bộ ngoặc riêng (1.3.692).
    private var tokenRuleDetail: String {
        let config = QuickTranslationBookEngineConfigStore.shared
        let tokenCount = config.overriddenTokenCount(bookId: bookId)
        let hasOwnBrackets = config.bracketPairs(bookId: bookId) != nil
        let parts: [String] = (tokenCount > 0 ? ["\(tokenCount) token"] : []) + (hasOwnBrackets ? ["bộ ngoặc"] : [])
        return parts.isEmpty ? "Đang theo cài đặt chung" : "Đang đặt riêng \(parts.joined(separator: " + "))"
    }

    private func scopePicker(_ label: String, selection: Binding<ScopeOverride>, inheritedTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                Text(inheritedTitle).tag(ScopeOverride.inherited)
                Text("Bật").tag(ScopeOverride.enabled)
                Text("Tắt").tag(ScopeOverride.disabled)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func ruleRow(title: String, detail: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kết quả

    private func refresh() {
        let current = store.isTranslationEnabled(bookId: bookId, packageId: packageId, isChineseSourceHint: isChineseSourceHint)
        if current != isEnabled { isEnabled = current }
    }

    /// Như `ReaderView` khi đổi hai công tắc chung: xoá cache dịch rồi báo `.translationDictionariesDidUpdate`.
    private func notifyEngineSettingChanged() {
        TranslationManager.shared.notifyDictionariesDidUpdate(bookId: nil, scope: .config(bookId: bookId))
    }
}
