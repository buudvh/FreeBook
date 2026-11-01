import SwiftUI
import SwiftData

/// Màn **Cấu hình tiện ích**: thẻ đầu (giới thiệu + Trình duyệt · Ghim · Gỡ) rồi các nhóm cài đặt **tự lưu**.
///
/// Không có nút "Lưu"/"Hủy"/"Đóng" — đóng bằng vuốt xuống (1.3.641). Mỗi nhóm ghi ngay qua `ExtensionTransactionCoordinator`:
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
    /// Khoá của `configDefinitions` theo thứ tự hiển thị: thứ tự trong `config` của `plugin.json`, rồi khoá đặc biệt ở gốc.
    @State internal var configKeys: [String] = []
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

    /// Một mục của khối `config` trong `plugin.json`. Dựng tay từ dict (không `JSONDecoder`): `default`/`values` viết
    /// bằng số hay bool vẫn đọc được (ép thành chuỗi) thay vì làm mất cả dòng.
    struct ConfigItem {
        let title: String?
        let subtitle: String?
        let mode: String?
        let format: String?
        let `default`: String?
        /// Lựa chọn của `mode: "select"`; rỗng với kiểu khác.
        let values: [String]

        init(title: String?, mode: String?, format: String?, default: String?) {
            self.title = title
            self.subtitle = nil
            self.mode = mode
            self.format = format
            self.default = `default`
            self.values = []
        }

        init(dictionary: [String: Any]) {
            title = dictionary["title"] as? String
            subtitle = dictionary["subtitle"] as? String
            mode = dictionary["mode"] as? String
            format = dictionary["format"] as? String
            `default` = dictionary["default"].map(ExtensionConfigValueFormatter.text)
            values = (dictionary["values"] as? [Any])?.map(ExtensionConfigValueFormatter.text) ?? []
        }
    }

    /// Giới hạn kết nối viết dạng giá trị trần dưới `config` (hợp đồng): không phải cài đặt nên không hiện. Vẫn được
    /// tiêm vào script (`ExtensionManager.getCombinedConfigs`). Viết thành object `{ title, mode }` thì là cài đặt thường.
    static let connectionKeys: Set<String> = ["thread_num", "delay", "ignore"]

    var body: some View {
        NavigationStack {
            sourceCheckPresentation(on: browserPresentation(on: uninstallDialogs(on: screenContent)))
                .pageTitle("Cấu hình tiện ích")
                .presentationDragIndicator(.visible)
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
                    onCheck: sourceCheckAction, // `+SourceCheck`
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
                var keys: [String] = []

                // 1. Đọc từ section "config" nếu có — theo thứ tự trong file
                if let configSection = json["config"] as? [String: Any] {
                    keys = Self.orderedConfigKeys(in: data, section: configSection)
                    for key in keys {
                        guard let value = configSection[key] else { continue }
                        if let dict = value as? [String: Any] {
                            definitions[key] = ConfigItem(dictionary: dict)
                        } else if Self.connectionKeys.contains(key) {
                            continue
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

                let declaredKeys = keys.filter { definitions[$0] != nil }
                let rootKeys = specialKeys.filter { definitions[$0] != nil && !declaredKeys.contains($0) }
                self.configDefinitions = definitions
                self.configKeys = declaredKeys + rootKeys
            }

            // Đọc các giá trị người dùng đã lưu trước đó trong Extension. Bỏ giá trị cũ của khoá kết nối đã ẩn (bản cũ
            // của màn này cho sửa): không còn chỗ sửa thì lượt ghi kế tiếp xoá nó, script về giá trị của `plugin.json`.
            var values: [String: String] = [:]
            if let userConfigData = current.configJson.data(using: .utf8),
               let savedValues = try? JSONSerialization.jsonObject(with: userConfigData) as? [String: Any] {
                for (k, v) in savedValues where !(Self.connectionKeys.contains(k) && configDefinitions[k] == nil) {
                    values[k] = ExtensionConfigValueFormatter.text(v)
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

    /// Khoá của khối `config` theo thứ tự trong file — `JSONSerialization` trả dict mất thứ tự, nên đọc lại bằng parser
    /// JSON giữ thứ tự sẵn có của engine Legado. Không đọc được ⇒ xếp ABC như trước. Tiện ích mã hoá cài trước 1.3.672
    /// đã bị ghi lại `plugin.json` theo ABC (`ExtensionScriptDecoder`) — phải cài lại mới có thứ tự gốc.
    private static func orderedConfigKeys(in data: Data, section: [String: Any]) -> [String] {
        let sorted = section.keys.sorted()
        guard let text = String(data: data, encoding: .utf8),
              let entries = LegadoEngineJSONParser.parse(text)?["config"]?.objectEntries else { return sorted }
        var seen = Set<String>()
        let ordered = entries.map { $0.key }.filter { section[$0] != nil && seen.insert($0).inserted }
        return ordered + sorted.filter { !seen.contains($0) }
    }
}
