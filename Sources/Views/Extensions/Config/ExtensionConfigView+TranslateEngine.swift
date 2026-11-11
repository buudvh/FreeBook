import SwiftUI

/// Hai mục riêng của tiện ích **loại `translate`** trên màn Cấu hình tiện ích, đặt ngay sau thẻ đầu:
///
/// - **Bộ dịch**: chọn Model (`model.js`) và Kiểu dịch (`style.js`) — cài đặt riêng của tiện ích, áp cho mọi truyện
///   dùng nó, ghi **ngay** qua `TranslationExtensionSettingsStore` (`""` = mặc định của tiện ích). Bộ chọn chỉ hiện khi
///   danh sách khác rỗng. Ngôn ngữ nguồn → đích không ở đây: chọn theo phạm vi ở popup dịch của Reader.
/// - **Dịch thử**: chạy `translate.js` một lần (`TranslationExtensionRunner.translateText`, `bookId: ""`,
///   `source: .untagged`, `bypassCache: true` ⇒ luôn gọi script) với model / kiểu dịch / config đang lưu. Ngôn ngữ của ô thử không lưu; mặc định = ngôn ngữ của
///   lựa chọn toàn cục nếu nó là tiện ích này, không thì `defaultLanguages`.
///
/// Danh sách (`TranslationExtensionCatalog`) đọc ở mức màn (`loadTranslateOptions`, gắn vào `NavigationStack` của
/// `ExtensionConfigView`), đọc lại khi config đã lưu đổi (vừa nhập khoá API). Lượt dịch thử do màn giữ
/// (`translateTrialTask`) và huỷ khi màn đóng. Tiện ích dịch không có nút Trình duyệt / Kiểm tra và không có nhóm Duyệt
/// và lịch sử / Trình duyệt (xem `configForm`).
extension ExtensionConfigView {
    /// Tiện ích dịch (`TranslationEngineStore.isTranslateExtension`, gom cả biến thể chữ của loại).
    internal var isTranslateEngine: Bool {
        TranslationEngineStore.isTranslateExtension(current)
    }

    /// Khoá của lượt đọc danh sách: `nil` ⇒ không phải tiện ích dịch đã cài, không đọc.
    internal var translateCatalogKey: String? {
        guard current.isInstalled, isTranslateEngine else { return nil }
        return current.configJson
    }

    @ViewBuilder
    internal var translateEngineSections: some View {
        if current.isInstalled, isTranslateEngine {
            TranslateEngineSections(
                packageId: ext.packageId,
                extensionName: current.name,
                options: translateOptions,
                loadError: translateOptionsError,
                trialTask: $translateTrialTask,
                flushPendingConfig: { flushPendingConfigSave() }
            )
        }
    }

    /// Đọc `language.js` / `model.js` / `style.js` (có cache theo dấu vân tay config trong catalog). Giữ danh sách cũ
    /// trong lúc đọc lại để bộ chọn không nháy.
    @MainActor
    internal func loadTranslateOptions() async {
        guard translateCatalogKey != nil else { return }
        let packageId = ext.packageId
        do {
            let options = try await TranslationExtensionCatalog.shared.options(packageId: packageId)
            translateOptions = options
            translateOptionsError = nil
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            translateOptionsError = TranslationExtensionResultParser.shortMessage(for: error)
            AppLogger.shared.log("❌ [ExtConfig] Không đọc được danh sách của tiện ích dịch \(packageId): \(translateOptionsError ?? "")")
        }
    }

    // MARK: - Hai mục

    struct TranslateEngineSections: View {
        let packageId: String
        let extensionName: String
        let options: TranslationExtensionCatalog.Options?
        let loadError: String?
        @Binding var trialTask: Task<Void, Never>?
        /// Ghi ngay config đang chờ debounce (vừa nhập khoá API) trước khi dịch thử.
        let flushPendingConfig: () -> Void

        /// Gương của `TranslationExtensionSettingsStore` (store không observe được).
        @State private var model: String
        @State private var style: String

        /// `nil` = chưa chọn ⇒ `defaultTrialLanguages`.
        @State private var trialFrom: String? = nil
        @State private var trialTo: String? = nil
        @State private var trialInput = ""
        @State private var trialResult = ""
        @State private var trialError = ""
        @State private var isTrialRunning = false

        private static let sampleText = "他转身走进了小巷。"

        init(
            packageId: String,
            extensionName: String,
            options: TranslationExtensionCatalog.Options?,
            loadError: String?,
            trialTask: Binding<Task<Void, Never>?>,
            flushPendingConfig: @escaping () -> Void
        ) {
            self.packageId = packageId
            self.extensionName = extensionName
            self.options = options
            self.loadError = loadError
            _trialTask = trialTask
            self.flushPendingConfig = flushPendingConfig
            _model = State(initialValue: TranslationExtensionSettingsStore.shared.model(packageId: packageId))
            _style = State(initialValue: TranslationExtensionSettingsStore.shared.style(packageId: packageId))
        }

        var body: some View {
            engineSection
            trialSection
        }

        // MARK: Bộ dịch

        private var engineSection: some View {
            Section {
                if let options {
                    if !options.models.isEmpty {
                        pickerRow("Model", items: options.models, selection: modelBinding)
                    }
                    if let description = selectedModelDescription {
                        Text(verbatim: description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !options.styles.isEmpty {
                        pickerRow("Kiểu dịch", items: options.styles, selection: styleBinding)
                    }
                    if options.models.isEmpty && options.styles.isEmpty {
                        Text("Tiện ích không có model hay kiểu dịch để chọn.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let loadError {
                    Text(verbatim: "Không đọc được danh sách của tiện ích: \(loadError)")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if options == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Đang đọc danh sách của tiện ích…")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                SectionHelpHeader("Bộ dịch", paragraphs: [
                    "**Model** và **Kiểu dịch** áp cho mọi truyện dùng tiện ích này làm bộ dịch. «Mặc định của tiện ích» để tiện ích tự chọn.",
                    "Chọn tiện ích làm bộ dịch và chọn ngôn ngữ nguồn → đích ở popup dịch trong màn đọc (nút dịch trên header), theo Truyện này / Nguồn này / Tất cả."
                ])
            }
        }

        private func pickerRow(_ title: String, items: [TranslationPickerOption], selection: Binding<String>) -> some View {
            let current = selection.wrappedValue
            return Picker(title, selection: selection) {
                Text("Mặc định của tiện ích").tag("")
                ForEach(items) { item in
                    Text(verbatim: item.name).tag(item.id)
                }
                // Mã đã lưu không còn trong danh sách (tiện ích vừa cập nhật): giữ một dòng để Picker có tag khớp.
                if !current.isEmpty, !items.contains(where: { $0.id == current }) {
                    Text(verbatim: "\(current) (không còn trong danh sách)").tag(current)
                }
            }
            .pickerStyle(.menu)
        }

        private var selectedModelDescription: String? {
            guard !model.isEmpty,
                  let description = options?.models.first(where: { $0.id == model })?.description,
                  !description.isEmpty else { return nil }
            return description
        }

        private var modelBinding: Binding<String> {
            Binding(
                get: { model },
                set: { value in
                    guard value != model else { return }
                    model = value
                    TranslationExtensionSettingsStore.shared.setModel(value, packageId: packageId)
                    AppLogger.shared.log("🌐 [ExtConfig] \(extensionName): model ⇒ \(value.isEmpty ? "mặc định" : value)")
                }
            )
        }

        private var styleBinding: Binding<String> {
            Binding(
                get: { style },
                set: { value in
                    guard value != style else { return }
                    style = value
                    TranslationExtensionSettingsStore.shared.setStyle(value, packageId: packageId)
                    AppLogger.shared.log("🌐 [ExtConfig] \(extensionName): kiểu dịch ⇒ \(value.isEmpty ? "mặc định" : value)")
                }
            )
        }

        // MARK: Dịch thử

        private var trialSection: some View {
            Section {
                LabeledContent("Ngôn ngữ") {
                    trialLanguageMenu
                }
                TextField(Self.sampleText, text: $trialInput, axis: .vertical)
                    .lineLimit(2...6)
                if !trialResult.isEmpty {
                    Text(verbatim: trialResult)
                        .font(.system(size: 15))
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                }
                if !trialError.isEmpty {
                    Text(verbatim: trialError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button(action: toggleTrial) {
                    HStack(spacing: 8) {
                        if isTrialRunning {
                            ProgressView()
                                .tint(.white)
                            Text("Đang dịch… (chạm để dừng)")
                        } else {
                            Image(systemName: "play")
                            Text("Dịch thử")
                        }
                    }
                }
                .buttonStyle(.appFilled)
            } header: {
                SectionHelpHeader("Dịch thử", paragraphs: [
                    "Chạy `translate.js` một lần với model, kiểu dịch và cấu hình (khoá API…) đang lưu. Để trống ô nhập ⇒ dịch câu mẫu.",
                    "Ngôn ngữ ở đây chỉ dùng cho ô thử, không lưu."
                ])
            }
        }

        private var trialLanguageMenu: some View {
            Menu {
                Picker(selection: trialFromBinding) {
                    ForEach(options?.sourceLanguages ?? []) { language in
                        Text(verbatim: language.name).tag(language.id)
                    }
                } label: {
                    Text("Dịch từ")
                }
                .pickerStyle(.menu)
                Picker(selection: trialToBinding) {
                    ForEach(options?.targetLanguages ?? []) { language in
                        Text(verbatim: language.name).tag(language.id)
                    }
                } label: {
                    Text("Dịch sang")
                }
                .pickerStyle(.menu)
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: "\(languageName(effectiveFrom, in: options?.sourceLanguages)) → "
                        + languageName(effectiveTo, in: options?.targetLanguages))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                }
            }
            .disabled(options == nil)
        }

        /// Ngôn ngữ mặc định của ô thử: cặp của lựa chọn toàn cục nếu nó là tiện ích này, không thì mặc định của tiện ích.
        private var defaultTrialLanguages: (from: String, to: String) {
            let global = TranslationEngineStore.shared.globalSelection
            if global.packageId == packageId { return (from: global.from, to: global.to) }
            if let options { return options.defaultLanguages }
            let quick = TranslationEngineSelection.quickTranslator
            return (from: quick.from, to: quick.to)
        }

        private var effectiveFrom: String { trialFrom ?? defaultTrialLanguages.from }
        private var effectiveTo: String { trialTo ?? defaultTrialLanguages.to }

        private var trialFromBinding: Binding<String> {
            Binding(get: { effectiveFrom }, set: { trialFrom = $0 })
        }

        private var trialToBinding: Binding<String> {
            Binding(get: { effectiveTo }, set: { trialTo = $0 })
        }

        private func languageName(_ code: String, in languages: [TranslationLanguageOption]?) -> String {
            languages?.first { $0.id == code }?.name ?? TranslationLanguageOption.displayName(forCode: code)
        }

        /// Bấm khi đang chạy ⇒ dừng; không thì chạy một lượt mới.
        private func toggleTrial() {
            if isTrialRunning {
                trialTask?.cancel()
                trialTask = nil
                isTrialRunning = false
                return
            }
            flushPendingConfig()
            let input = trialInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = input.isEmpty ? Self.sampleText : input
            let job = TranslationExtensionRunner.Job(
                packageId: packageId, bookId: "", from: effectiveFrom, to: effectiveTo, source: .untagged
            )
            trialResult = ""
            trialError = ""
            isTrialRunning = true
            trialTask?.cancel()
            trialTask = Task {
                do {
                    // Dịch thử luôn gọi script (không lấy bản dịch / lỗi đã nhớ) — vừa sửa khoá API là thấy ngay.
                    let output = try await TranslationExtensionRunner.translateText(text, job: job, bypassCache: true)
                    guard !Task.isCancelled else { return }
                    trialResult = output
                } catch {
                    guard !(error is CancellationError), !Task.isCancelled else { return }
                    trialError = TranslationExtensionResultParser.shortMessage(for: error)
                }
                isTrialRunning = false
            }
        }
    }
}
