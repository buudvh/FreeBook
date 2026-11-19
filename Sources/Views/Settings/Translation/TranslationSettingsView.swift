import SwiftUI

/// Màn "Cài đặt dịch thuật" (Cài đặt → Đọc & Nghe). Chuyển từ `SettingsView` (1.3.520): section "Dịch Thuật Quick
/// Translate" và "Từ điển chung".
///
/// Từ điển chung là lưới 5 thẻ VietPhrase.txt / Name.txt / PhienAm.txt / Pronouns.txt / **Rule dịch** (thay ô LuatNhan đã
/// gỡ); mỗi thẻ là `Menu` thả xuống Sửa / Nhập file (popup 3 cách nhập) / Xuất file / Làm mới dữ liệu / Xoá —
/// `GlobalDictionaryCardMenu` + `GlobalDictionaryCardController` + `GlobalDictionaryCardPresentations`.
struct TranslationSettingsView: View {
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @AppStorage("isTranslationPronounsEnabled") private var isTranslationPronounsEnabled = false
    @ObservedObject private var translationManager = TranslationManager.shared
    @ObservedObject private var ruleStore = QuickTranslationRuleStore.shared

    /// Tập "đang nhập" phải sống lâu hơn màn này (xem `TranslationImportState`).
    @ObservedObject private var importState = TranslationImportState.shared
    private var importingTypes: Set<String> { importState.importingTypes }
    @StateObject private var cards = GlobalDictionaryCardController()

    var body: some View {
        Form { Group {
            Section(header: Text("Dịch Thuật Quick Translate")) {
                HelpLabeledToggle(
                    title: "Bật dịch Quick Translate",
                    titleFont: .body.weight(.medium),
                    help: ["Tự động dịch siêu dữ liệu và nội dung truyện chữ tiếng Trung sang tiếng Việt (Hán-Việt/VietPhrase)."],
                    isOn: $isTranslationEnabled
                )
                .onChange(of: isTranslationEnabled) { _, newValue in
                    TranslateUtils.clearCache()
                    TranslationManager.shared.notifyRulesDidUpdate()
                }
                NavigationLink(destination: TOCRulesConfigView()) {
                    Label("Quản lý quy tắc TOC", systemImage: "list.bullet.indent")
                }
                .disabled(!importingTypes.isEmpty)
                NavigationLink(destination: JunkFilterManagementView()) {
                    Label("Quản lý lọc rác", systemImage: "trash.slash")
                }
                .disabled(!importingTypes.isEmpty)
                NavigationLink(destination: TranslationScopeManagementView()) {
                    Label("Cấu hình dịch theo Nguồn & Truyện", systemImage: "slider.horizontal.3")
                }
                .disabled(!importingTypes.isEmpty)
                QuickTranslateRuleSettingsRows(
                    isTranslationEnabled: isTranslationEnabled,
                    isBusy: !importingTypes.isEmpty
                )

                if isTranslationEnabled {
                    Toggle(isOn: $isTranslationPronounsEnabled) {
                        Text("Dịch Đại từ (Pronouns)")
                            .font(.subheadline)
                    }
                    .padding(.leading, 16)
                    .onChange(of: isTranslationPronounsEnabled) { _, _ in
                        TranslateUtils.clearCache()
                        TranslationManager.shared.notifyDictionariesDidUpdate()
                    }
                }
            }

            if isTranslationEnabled {
                Section(header: Text("Từ điển chung")) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(GlobalDictionaryCardController.Kind.allCases) { kind in
                                GlobalDictionaryCardMenu(
                                    kind: kind,
                                    statusText: statusText(for: kind),
                                    isSet: isSet(kind),
                                    controller: cards
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if translationManager.isDownloading {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(translationManager.downloadMessage)
                                .font(.caption)
                            ProgressView(value: translationManager.downloadProgress)
                        }
                    } else if !translationManager.isDownloaded() {
                        // Đã có dữ liệu VietPhrase thì ẩn hẳn nút này: nút "Làm mới" bên dưới lo
                        // việc nạp lại, còn tải lại từ mạng chỉ có ích khi chưa có dữ liệu.
                        Button(action: {
                            Task {
                                await translationManager.downloadDefaultDictionaries()
                                await MainActor.run {
                                    DictionaryCache.shared.invalidateAll()
                                }
                            }
                        }) {
                            Label("Tải từ điển mặc định", systemImage: "arrow.down.circle")
                        }
                        .disabled(!importingTypes.isEmpty)
                    }

                    // Cùng một hàm với mục "Làm mới dữ liệu" của mọi thẻ.
                    Button(action: { cards.refreshTranslationData() }) {
                        HStack {
                            Label("Làm mới dữ liệu dịch", systemImage: "arrow.clockwise")
                            if importingTypes.contains("refresh") {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!importingTypes.isEmpty)

                    NavigationLink(destination: SearchEnginesConfigView()) {
                        Label("Cấu hình công cụ tra cứu", systemImage: "magnifyingglass")
                    }
                    .disabled(!importingTypes.isEmpty)
                }
        }.glassSheetRows() }
        .backPageTitle("Cài đặt dịch thuật")
        .modifier(GlobalDictionaryCardPresentations(controller: cards))
    }

    private func isSet(_ kind: GlobalDictionaryCardController.Kind) -> Bool {
        switch kind {
        case .vietPhrase: return translationManager.isVietPhraseLoaded
        case .names: return translationManager.isNamesLoaded
        case .phienAm: return translationManager.isPhienAmLoaded
        case .pronouns: return translationManager.isPronounsLoaded
        case .rules: return ruleStore.status.hasFile
        }
    }

    private func statusText(for kind: GlobalDictionaryCardController.Kind) -> String {
        if importingTypes.contains(kind.rawValue) {
            return "Đang xử lý..."
        }
        if cards.exportingKind == kind {
            return "Đang xuất..."
        }
        if kind == .rules {
            return ruleStore.status.hasFile ? "\(ruleStore.status.ruleCount) rule" : "<Chưa thiết lập>"
        }
        if let count = translationManager.getWordCount(for: kind.rawValue) {
            return "\(count) từ"
        }
        return "<Chưa thiết lập>"
    }
}
