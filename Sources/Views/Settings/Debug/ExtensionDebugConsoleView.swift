import SwiftData
import SwiftUI

/// Màn debug extension của Phase 1: chọn extension đã cài, chọn entrypoint, nhập input, chạy và xem
/// trace thời gian thực.
///
/// Ranh giới cố ý: view **chỉ đọc** (`@Query`) và gọi `ExtensionDebugRunner`; mọi việc chạy JS, redact
/// và buffer nằm ở tầng Services. Trace ở đây **không** phụ thuộc `AppLogger.isLoggingEnabled` — đó là
/// lý do màn này tồn tại thay vì đọc `app_logs.txt`.
struct ExtensionDebugConsoleView: View {
    @Query(sort: \Extension.name) private var extensions: [Extension]
    @StateObject private var trace = ExtensionDebugTraceReader()

    @State private var selectedPackageId: String = ""
    @State private var selectedKey: String = "search"
    @State private var keyword: String = ""
    @State private var page: Int = 1
    @State private var inputUrl: String = ""
    @State private var customFileName: String = ""
    @State private var customInput: String = ""
    @State private var customPageUrl: String = ""

    private var runnableExtensions: [Extension] {
        extensions.filter { !$0.localPath.isEmpty && $0.type != "tts" }
    }

    private var selectedExtension: Extension? {
        runnableExtensions.first { $0.packageId == selectedPackageId }
    }

    private var isCustom: Bool { selectedKey == "__custom__" }

    /// Với sáu entrypoint chuẩn thì "có sẵn" nghĩa là `plugin.json` khai khoá đó; custom script resolve
    /// theo tên file nên chỉ cần người dùng đã nhập tên.
    private var scriptAvailable: Bool {
        guard let ext = selectedExtension else { return false }
        if isCustom { return !customFileName.trimmingCharacters(in: .whitespaces).isEmpty }
        return ExtensionManager.shared.hasScript(localPath: ext.localPath, scriptKey: selectedKey)
    }

    private var canRun: Bool {
        guard selectedExtension != nil, scriptAvailable, !trace.isRunning else { return false }
        switch selectedKey {
        case "search": return !keyword.trimmingCharacters(in: .whitespaces).isEmpty
        case "detail", "toc", "chap": return !inputUrl.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    var body: some View {
        Form {
            targetSection
            inputSection
            actionSection
            traceSection
        }
        .navigationTitle("Debug Extension")
        .task {
            trace.attach()
            if selectedPackageId.isEmpty {
                selectedPackageId = runnableExtensions.first?.packageId ?? ""
            }
        }
    }

    private var targetSection: some View {
        Section {
            Picker("Extension", selection: $selectedPackageId) {
                ForEach(runnableExtensions, id: \.packageId) { ext in
                    Text("\(ext.name) (v\(ext.version))").tag(ext.packageId)
                }
            }

            Picker("Entrypoint", selection: $selectedKey) {
                ForEach(ExtensionDebugEntrypoint.allTemplates, id: \.selectionKey) { template in
                    Text(template.displayName).tag(template.selectionKey)
                }
            }

            if selectedExtension != nil, !scriptAvailable, !isCustom {
                Label("Extension này không khai script \"\(selectedKey)\" trong plugin.json", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Nguồn chạy")
        } footer: {
            Text("Chỉ chạy được extension đã cài trong app (source mode installed). Nạp mã từ máy phát triển là Phase 3.")
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        Section("Input execute(...)") {
            switch selectedKey {
            case "search":
                TextField("keyword", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Stepper("page: \(page)", value: $page, in: 1...50)
            case "detail", "toc", "chap":
                TextField("url", text: $inputUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            case "__custom__":
                TextField("tên file script (vd: list.js)", text: $customFileName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("input (dùng {0} cho số trang)", text: $customInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Stepper("page: \(page)", value: $page, in: 1...50)
                if page > 1 {
                    TextField("pageUrl (chỉ dùng từ trang 2)", text: $customPageUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            default:
                Text("execute() không nhận tham số")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button(action: startRun) {
                Label(trace.isRunning ? "Đang chạy…" : "Chạy execute(...)", systemImage: "play.fill")
            }
            .disabled(!canRun)

            Button(role: .destructive, action: cancelRun) {
                Label("Huỷ run", systemImage: "stop.fill")
            }
            .disabled(!trace.isRunning)

            Button(action: { trace.clear() }) {
                Label("Xoá trace", systemImage: "trash")
            }
            .disabled(trace.allEvents.isEmpty)
        }
    }

    @ViewBuilder
    private var traceSection: some View {
        Section {
            if trace.visibleEvents.isEmpty {
                Text("Chưa có event nào.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trace.visibleEvents) { event in
                    ExtensionDebugEventRow(event: event)
                }
            }
        } header: {
            HStack {
                Text("Trace")
                Spacer()
                Text("\(trace.visibleEvents.count) event · \(trace.errorCount) lỗi")
                    .font(.caption2)
                    .foregroundStyle(trace.errorCount > 0 ? .red : .secondary)
            }
        } footer: {
            Text("Trace không phụ thuộc cấu hình ghi log, và đã bỏ header/cookie/body/nội dung chương. Giá trị query trong URL hiện dưới dạng “…”.")
        }
    }

    private func startRun() {
        guard let ext = selectedExtension, let entrypoint = makeEntrypoint() else { return }
        let localPath = ext.localPath
        let downloadUrl = ext.downloadUrl
        let configJson = ext.configJson
        let packageId = ext.packageId
        // Cùng fallback host mà production dùng khi không có `Book.host`: xem
        // `BookDetailView.resolvedHost`. Debug không có sách nên đây là bậc cuối cùng của chuỗi đó.
        let host = ext.sourceUrl
        Task {
            let runId = await ExtensionDebugRunner.shared.start(
                packageId: packageId,
                localPath: localPath,
                downloadUrl: downloadUrl,
                configJson: configJson,
                host: host,
                entrypoint: entrypoint
            )
            trace.markStarted(runId: runId)
        }
    }

    private func cancelRun() {
        guard let runId = trace.focusedRunId else { return }
        Task { await ExtensionDebugRunner.shared.cancel(runId: runId) }
    }

    private func makeEntrypoint() -> ExtensionDebugEntrypoint? {
        let url = inputUrl.trimmingCharacters(in: .whitespaces)
        switch selectedKey {
        case "search": return .search(keyword: keyword.trimmingCharacters(in: .whitespaces), page: page)
        case "detail": return .detail(url: url)
        case "toc": return .toc(url: url)
        case "chap": return .chap(url: url)
        case "genre": return .genre
        case "home": return .home
        case "__custom__":
            return .custom(
                fileName: customFileName.trimmingCharacters(in: .whitespaces),
                input: customInput,
                page: page,
                pageUrl: customPageUrl.isEmpty ? nil : customPageUrl
            )
        default: return nil
        }
    }
}
