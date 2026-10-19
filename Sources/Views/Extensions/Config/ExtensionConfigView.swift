import SwiftUI
import SwiftData

/// Màn **Cấu hình tiện ích**: thẻ đầu (giới thiệu + Trình duyệt · Ghim · Gỡ) rồi các nhóm cài đặt **tự lưu**.
///
/// Không còn nút "Lưu"/"Hủy" — chỉ "Đóng". Mỗi nhóm ghi ngay qua `ExtensionTransactionCoordinator`:
/// biến cấu hình + cookie ở `ExtensionConfigView+GlobalConfig`, lịch sử + 18+ ở `+History`/`+Nsfw`, chặn quảng cáo
/// + chế độ máy tính của webview ở `+WebContent`, gỡ ở `+Uninstall`, trình duyệt của nguồn ở `+Browser`. Khối
/// `plugin.json` nằm ở màn con `ExtensionMetadataScreen`.
///
/// Mọi `@State` để `internal`: các file `+` là extension ở file khác, mà `private` chỉ có phạm vi **file**.
/// `onImport` có mặc định `nil` nên Quản lý tiện ích và màn TTS vẫn gọi `ExtensionConfigView(ext:)` như cũ.
struct ExtensionConfigView: View {
    @Environment(\.dismiss) internal var dismiss

    var ext: Extension
    /// Khám phá truyền vào để **tự** mở màn Chi tiết sau khi bấm "Import truyện" trong trình duyệt của nguồn.
    /// `nil` (Quản lý tiện ích, TTS) ⇒ màn này tự đẩy Chi tiết trong `NavigationStack` của nó.
    var onImport: ((_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void)? = nil

    /// `ext` là snapshot giá trị lúc mở màn — tra lại theo `packageId` để thấy tên/config vừa lưu.
    internal var current: Extension {
        ExtensionLibraryRepository.shared.installedExtension(packageId: ext.packageId) ?? ext
    }

    // Lưu các cấu hình định nghĩa trong plugin.json
    @State internal var configDefinitions: [String: ConfigItem] = [:]
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

    struct ConfigItem: Codable {
        let title: String?
        let mode: String?
        let format: String?
        let `default`: String?
    }

    var body: some View {
        NavigationStack {
            browserPresentation(on: uninstallDialogs(on: screenContent))
                .navigationTitle("Cấu hình tiện ích")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Đóng") {
                            dismiss()
                        }
                    }
                }
                .sheet(isPresented: $showingScriptEditor) {
                    ExtensionScriptEditorView(ext: current)
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
        Form {
            Section {
                ExtensionConfigHeaderCard(
                    ext: current,
                    onOpenBrowser: openBrowserAction, // `+Browser`
                    onUninstall: uninstallAction // `+Uninstall`
                )
            }

            globalConfigSection // tự lưu — `ExtensionConfigView+GlobalConfig`
            browsingAndHistorySection // tự lưu khi bấm — `ExtensionConfigView+History` / `+Nsfw`
            webContentSection // tự lưu khi bấm — `ExtensionConfigView+WebContent`
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
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
        .scrollDismissesKeyboard(.interactively)
        // Bớt khoảng trống mặc định giữa các nhóm và phía trên thẻ đầu (iOS 17).
        .listSectionSpacing(.compact)
    }

    internal func loadConfigDefinitions() {
        guard !current.localPath.isEmpty else {
            errorMessage = "Tiện ích chưa được cài đặt cục bộ."
            isLoading = false
            return
        }

        let extUrl = URL(fileURLWithPath: current.localPath)
        let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")

        guard FileManager.default.fileExists(atPath: pluginJsonUrl.path) else {
            errorMessage = "Không tìm thấy tệp plugin.json"
            isLoading = false
            return
        }

        do {
            let data = try Data(contentsOf: pluginJsonUrl)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var definitions: [String: ConfigItem] = [:]

                // 1. Đọc từ section "config" nếu có
                if let configSection = json["config"] as? [String: Any] {
                    for (key, value) in configSection {
                        if let dict = value as? [String: Any] {
                            if let dictData = try? JSONSerialization.data(withJSONObject: dict),
                               let item = try? JSONDecoder().decode(ConfigItem.self, from: dictData) {
                                definitions[key] = item
                            }
                        } else if let bVal = value as? Bool {
                            definitions[key] = ConfigItem(title: key, mode: "toggle", format: "boolean", default: "\(bVal)")
                        } else if let nVal = value as? NSNumber {
                            definitions[key] = ConfigItem(title: key, mode: "input", format: "number", default: "\(nVal)")
                        } else if let sVal = value as? String {
                            definitions[key] = ConfigItem(title: key, mode: "input", format: "text", default: sVal)
                        }
                    }
                }

                // 2. Đọc các trường thô đặc biệt ở root plugin.json nếu chưa có trong config
                let specialKeys = ["preload_size", "max_length", "required_api_key", "support_url"]
                for key in specialKeys {
                    if definitions[key] == nil, let val = json[key] {
                        if let bVal = val as? Bool {
                            definitions[key] = ConfigItem(title: key, mode: "toggle", format: "boolean", default: "\(bVal)")
                        } else if let nVal = val as? NSNumber {
                            definitions[key] = ConfigItem(title: key, mode: "input", format: "number", default: "\(nVal)")
                        } else if let sVal = val as? String {
                            definitions[key] = ConfigItem(title: key, mode: "input", format: "text", default: sVal)
                        }
                    }
                }

                self.configDefinitions = definitions
            }

            // Đọc các giá trị người dùng đã lưu trước đó trong Extension
            var values: [String: String] = [:]
            if let userConfigData = current.configJson.data(using: .utf8),
               let savedValues = try? JSONSerialization.jsonObject(with: userConfigData) as? [String: Any] {
                for (k, v) in savedValues {
                    values[k] = Self.storedValueText(v)
                }
            }

            // Điền sẵn các giá trị mặc định cho những key chưa được lưu
            for (key, definition) in configDefinitions where values[key] == nil {
                values[key] = definition.default ?? ""
            }
            if values[Self.cookieKey] == nil {
                values[Self.cookieKey] = "true"
            }

            // Mốc so sánh lấy SAU khi điền mặc định: lượt `onChange` do lần gán này bắn ra thấy hai bản bằng nhau
            // nên không ghi gì.
            self.persistedConfigValues = values
            self.userValues = values
            isLoading = false
        } catch {
            errorMessage = "Lỗi xử lý file plugin.json: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// `JSONSerialization` trả bool dưới dạng `NSNumber`; nội suy `"\(v)"` ra `"1"`/`"0"` nên công tắc (so với
    /// `"true"`) luôn hiện tắt và lần ghi sau biến `true` thành `false`. Nhận diện bool thật qua `CFBoolean`.
    private static func storedValueText(_ value: Any) -> String {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        return "\(value)"
    }
}
