import SwiftUI
import SwiftData

/// Màn **Cấu hình tiện ích**: thẻ đầu (giới thiệu + Trình duyệt · Ghim · Gỡ) rồi các nhóm cài đặt **tự lưu**.
///
/// Không có nút "Lưu"/"Hủy"/"Đóng" — đóng bằng vuốt xuống (1.3.641). Mỗi nhóm ghi ngay qua `ExtensionTransactionCoordinator`:
/// biến cấu hình + cookie ở `ExtensionConfigView+GlobalConfig`, lịch sử + 18+ ở `+History`/`+Nsfw`, chặn quảng cáo
/// + chế độ máy tính của webview ở `+WebContent`, kiểu vuốt xuống trình phát (tiện ích video) ở `+Video`, gỡ ở `+Uninstall`, trình duyệt của nguồn ở `+Browser`, trang đăng
/// nhập `support_url` ở `+SupportLink`. Khối `plugin.json` nằm ở màn con `ExtensionMetadataScreen`. Tiện ích loại
/// `translate` có thêm Bộ dịch (model, kiểu dịch) + Dịch thử ở `+TranslateEngine`, không có Trình duyệt / Kiểm tra /
/// Duyệt và lịch sử / chặn quảng cáo của webview.
///
/// Mọi `@State` để `internal`: các file `+` là extension ở file khác, mà `private` chỉ có phạm vi **file**.
/// `onImport` có mặc định `nil` nên Quản lý tiện ích và màn TTS vẫn gọi `ExtensionConfigView(ext:)` như cũ.
struct ExtensionConfigView: View {
    @Environment(\.dismiss) internal var dismiss
    /// Container cho màn xem phim: "Import" phim từ trình duyệt của nguồn video mở màn xem thay cho Chi tiết.
    @Environment(\.modelContext) internal var modelContext

    var ext: Extension
    /// Khám phá truyền vào để **tự** mở màn Chi tiết sau khi bấm "Import truyện" trong trình duyệt của nguồn.
    /// `nil` (Quản lý tiện ích, TTS) ⇒ màn này tự đẩy Chi tiết trong `NavigationStack` của nó.
    var onImport: ((_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void)? = nil

    /// `ext` là snapshot giá trị lúc mở màn — tra lại theo `packageId` để thấy tên/config vừa lưu.
    internal var current: Extension {
        ExtensionLibraryRepository.shared.installedExtension(packageId: ext.packageId) ?? ext
    }

    /// Các mục cài đặt khai trong plugin.json, theo thứ tự hiển thị.
    @State internal var configSchema = ExtensionConfigSchema()
    // Lưu các giá trị hiện tại người dùng nhập vào
    @State internal var userValues: [String: String] = [:]
    /// Bản đã ghi gần nhất (hoặc bản vừa nạp) — mốc so sánh để không sinh lượt ghi giả. `+GlobalConfig`
    @State internal var persistedConfigValues: [String: String] = [:]
    @State internal var configSaveTask: Task<Void, Never>? = nil
    @State internal var configSaveError = ""

    @State internal var isLoading = true
    @State internal var errorMessage = ""
    @State internal var showingScriptEditor = false
    @State internal var showingUninstallConfirm = false
    @State internal var uninstallAlertMessage = "" // lỗi/chặn gỡ — `ExtensionConfigView+Uninstall`

    // Trình duyệt của nguồn + đích Chi tiết khi Import mà không có `onImport` — `ExtensionConfigView+Browser`
    @State internal var showingBrowser = false
    @State internal var importedBook: ImportedBookRoute? = nil
    @State internal var navigateToImportedBook = false
    @State internal var showingSourceCheck = false // `+SourceCheck`
    // Trang đăng nhập `support_url` — `ExtensionConfigView+SupportLink`
    @State internal var supportLinkURL: String? = nil
    @State internal var openingSupportLink: SupportLinkRoute? = nil
    // Tiện ích dịch: danh sách language/model/style + lượt Dịch thử đang chạy — `ExtensionConfigView+TranslateEngine`
    @State internal var translateOptions: TranslationExtensionCatalog.Options? = nil
    @State internal var translateOptionsError: String? = nil
    @State internal var translateTrialTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            supportLinkPresentation(on: sourceCheckPresentation(on: browserPresentation(on: uninstallDialogs(on: screenContent))))
                .pageTitle("Cấu hình tiện ích")
                .presentationDragIndicator(.visible)
                .sheet(isPresented: $showingScriptEditor) {
                    Group {
                        ExtensionScriptEditorView(ext: current)
                    }
                    .appGlassSheet()
                }
                .onChange(of: userValues) { oldValues, newValues in
                    handleConfigChange(from: oldValues, to: newValues)
                }
        }
        // Gắn ở `NavigationStack` (không phải nội dung bên trong): đẩy màn plugin.json / Chi tiết truyện làm
        // nội dung gốc nhận `onAppear`/`onDisappear` mỗi lần, còn stack chỉ nhận khi sheet thật sự mở/đóng.
        .onAppear {
            if isLoading { loadConfigDefinitions() }
        }
        .onDisappear {
            flushPendingConfigSave() // ghi ngay lượt đang chờ debounce, không bỏ
            translateTrialTask?.cancel() // rời màn ⇒ dừng lượt Dịch thử
            translateTrialTask = nil
        }
        // Chỉ tiện ích dịch đã cài (khoá `nil` ⇒ không làm gì); config đã lưu đổi ⇒ đọc lại danh sách.
        .task(id: translateCatalogKey) {
            await loadTranslateOptions()
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        if isLoading {
            ProgressView("Đang đọc cấu hình...")
        } else if !errorMessage.isEmpty {
            loadErrorView
        } else {
            configForm
        }
    }

    private var loadErrorView: some View {
        VStack(spacing: 16) {
            Text("Lỗi đọc cấu hình")
                .font(.headline)
            Button(action: { dismiss() }) {
                Text("Đóng")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var configForm: some View {
        Form { Group {
            Section {
                // Tiện ích dịch không có trang để duyệt hay script nội dung để kiểm tra.
                ExtensionConfigHeaderCard(
                    ext: current,
                    onOpenBrowser: isTranslateEngine ? nil : openBrowserAction, // `+Browser`
                    onCheck: isTranslateEngine ? nil : sourceCheckAction, // `+SourceCheck`
                    onUninstall: uninstallAction // `+Uninstall`
                )
            }

            translateEngineSections // Bộ dịch + Dịch thử, chỉ tiện ích dịch — `ExtensionConfigView+TranslateEngine`
            supportLinkSection // nút mở trang đăng nhập — `ExtensionConfigView+SupportLink`
            globalConfigSection // tự lưu — `ExtensionConfigView+GlobalConfig`
            if !isTranslateEngine {
                browsingAndHistorySection // tự lưu khi bấm — `ExtensionConfigView+History` / `+Nsfw`
                webContentSection // tự lưu khi bấm — `ExtensionConfigView+WebContent`
            }
            videoSection // tự lưu khi chọn, chỉ tiện ích video — `ExtensionConfigView+Video`
            networkSection // tự lưu — `ExtensionConfigView+GlobalConfig`

            Section(header: Text("Nâng cao")) {
                NavigationLink {
                    ExtensionMetadataScreen(ext: current)
                } label: {
                    Label("Thông tin plugin.json", systemImage: "doc.text")
                }
                Button(action: {
                    showingScriptEditor = true
                }) {
                    Label("Sửa mã nguồn Script", systemImage: "code.square")
                        .foregroundColor(.primary)
                }
            }
        }.glassSheetRows() }
        .scrollDismissesKeyboard(.interactively)
        // Bớt khoảng trống mặc định giữa các nhóm và phía trên thẻ đầu (iOS 17).
        .listSectionSpacing(.compact)
    }

    internal func loadConfigDefinitions() {
        do {
            let schema = try ExtensionConfigSchema.load(localPath: current.localPath)
            supportLinkURL = schema.supportLinkURL // nút, không phải cài đặt — `+SupportLink`
            configSchema = schema
            let values = schema.initialValues(configJson: current.configJson)
            // Mốc so sánh lấy SAU khi điền mặc định: lượt `onChange` do lần gán này bắn ra thấy hai bản bằng nhau
            // nên không ghi gì.
            persistedConfigValues = values
            userValues = values
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
