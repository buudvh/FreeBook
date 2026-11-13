import SwiftUI
import SwiftData

struct TTSSettingsView: View {
    let isPresentedAsSheet: Bool

    @Environment(\.presentationMode) var presentationMode
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var ttsManager = TTSManager.shared

    /// `catalog` (gồm cả nguồn chưa cài) như `@Query` cũ; danh sách chọn engine lọc lại chỉ bản đã cài.
    private var allExtensions: [Extension] { ExtensionLibraryRepository.shared.catalog }

    private var ttsExtensions: [Extension] {
        ExtensionLibraryRepository.shared.installed.filter { $0.type == ExtensionType.tts }
    }

    @State private var selectedExtForConfig: Extension? = nil
    /// `internal` (không còn `private`): được đọc/ghi từ `TTSSettingsView+Voice.swift`.
    @State var showingReplacementManagerSheet = false
    @AppStorage("google_cloud_tts_custom_api_key") private var customGoogleApiKey: String = ""
    @State private var showApiKey: Bool = false
    /// `false` khi màn bị gỡ khỏi stack / sheet đóng; vẫn `true` khi chỉ bị trang con hay tab khác che (1.3.897).
    @Environment(\.isPresented) private var isPresented
    /// Tốc độ **tổng hợp** của VieNeu (1.3.465) — đưa thẳng vào model, **nhân** với `ttsManager.speed`
    /// thành tốc độ nghe. `@State` vì thanh trượt cần một giá trị quan sát được; giá trị thật nằm ở
    /// `UserDefaults` và được làm mới trong `refreshVieNeuSettings()` (bài học 1.3.456).
    @State var vieNeuSynthesisSpeed: Double = VieNeuSynthesisPolicy.synthesisSpeed(from: .standard)
    /// Hai cờ tiếng Nhật của VieNeu + trạng thái "đã tải từ điển". Gom vào **một** `ObservableObject` vì
    /// file này chỉ còn **3 dòng** tới trần 519 của `check_architecture.py` — xem `VieNeuJapaneseFlags`.
    @StateObject var vieNeuJapaneseFlags = VieNeuJapaneseFlags()
    /// Sheet chọn giọng VieNeu (1.3.900) — gắn ở gốc `Form`, mở từ hàng "Giọng đọc".
    @State var showingVieNeuVoicePicker = false
    /// Sheet chọn giọng của Siri / NghiTTS / Google / tiện ích — mở từ hàng "Giọng đọc".
    @State private var voicePickerEngine: TTSVoiceEngine?

    private var currentExtParams: (preloadSize: Int?, maxLength: Int?) {
        let path = allExtensions.first(where: { $0.packageId == ttsManager.tool })?.localPath ?? ttsManager.extensionLocalPath
        return ttsManager.parseExtensionConfigParams(jsonString: ttsManager.extensionConfigJson, localPath: path)
    }

    var body: some View {
        Form { Group {
            // Section 1: Chọn trình đọc
            Section("Trình đọc") {
                Picker("Trình đọc", selection: readerPickerSelection) {
                    Text("Siri (Hệ thống Apple)").tag("system")
                    Text("NghiTTS (Piper Offline)").tag("nghitts")
                    vieNeuPickerRows
                    Text("Google Cloud TTS (Online)").tag("google")
                    ForEach(ttsExtensions) { ext in
                        Text(ext.name).tag(ext.packageId)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Section 2: Chọn giọng đọc — một hàng tóm tắt, bấm ⇒ sheet chọn giọng của trình đọc.
            Section("Giọng đọc") {
                if let engine = TTSVoiceEngine(tool: ttsManager.tool) {
                    TTSReaderVoiceSummaryRow(engine: engine) { voicePickerEngine = engine }
                } else {
                    vieNeuVoicePicker
                }
            }

            // Section 3: Quản lý riêng của trình đọc
            Section {
                if ttsManager.tool == "google" {
                    HStack {
                        Text("Trạng thái Key hệ thống:")
                        Spacer()
                        if GoogleTTSService.shared.hasApiKey {
                            Label("Đã sẵn sàng", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundColor(.green)
                        } else {
                            Label("Chưa có Key", systemImage: "xmark.circle.fill")
                                .font(.caption).foregroundColor(.red)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key cá nhân (Ghi đè key hệ thống):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if showApiKey {
                                TextField("Nhập Google Cloud API Key...", text: $customGoogleApiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.none)
                            } else {
                                SecureField("Nhập Google Cloud API Key...", text: $customGoogleApiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: { showApiKey.toggle() }) {
                                Image(systemName: showApiKey ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if ttsManager.tool == "nghitts" {
                    NavigationLink(destination: NghiTTSSettingsHubView()) {
                        Label("Cài đặt NghiTTS", systemImage: "waveform.and.mic")
                    }
                    NavigationLink(destination: NghiTTSSettingsView()) {
                        Label("Cấu hình tiền xử lý & ngắt nghỉ", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink(destination: TTSDictionaryEditView()) {
                        Label("Từ điển phiên âm cá nhân", systemImage: "character.book.closed")
                    }
                } else if ttsManager.tool == "vieneu" {
                    vieNeuReaderSection
                } else if ttsManager.tool != "system" {
                    if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }) {
                        Button(action: { self.selectedExtForConfig = ext }) {
                            HStack {
                                Label("Cấu hình Extension (\(ext.name))", systemImage: "slider.horizontal.3")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Siri hệ thống không cần cấu hình quản lý riêng.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } header: {
                readerManagementHeader
            }

            voiceSection

            numberPreprocessingSection

            // Section 5: Tải trước dữ liệu
            Section(header: HStack {
                Text("Tải trước dữ liệu")
                Spacer()
                Button(action: { ttsManager.resetPrefetchSettings() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Đặt lại")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                }
            }) {
                if ttsManager.tool == "google" {
                    Stepper(value: $ttsManager.googlePrefetchCount, in: 2...10) {
                        HStack {
                            Text("Số đoạn tải trước (Google TTS):")
                            Spacer()
                            Text("\(ttsManager.googlePrefetchCount) đoạn")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    Stepper(value: $ttsManager.chunkLength, in: 50...500, step: 10) {
                        HStack {
                            Text("Độ dài đoạn văn (Google TTS):")
                            Spacer()
                            Text("\(ttsManager.chunkLength) ký tự")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                } else if ttsManager.tool == "nghitts" {
                    VStack(alignment: .leading, spacing: 6) {
                        Stepper(
                            value: Binding(
                                get: { ttsManager.nghittsSafeCachedTimeThreshold },
                                set: { ttsManager.setNghiTTSSafeCachedTimeThreshold($0) }
                            ),
                            in: 4...20,
                            step: 1
                        ) {
                            HStack {
                                Text("Ngưỡng nạp bộ đệm (NghiTTS):")
                                Spacer()
                                Text("\(Int(ttsManager.nghittsSafeCachedTimeThreshold))s")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                        }
                        Text("Tự động tổng hợp thêm âm thanh khi thời lượng đệm âm thanh liên tục còn lại giảm xuống dưới \(Int(ttsManager.nghittsSafeCachedTimeThreshold)) giây.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Stepper(value: $ttsManager.chunkLength, in: 50...500, step: 10) {
                        HStack {
                            Text("Độ dài phân đoạn (NghiTTS):")
                            Spacer()
                            Text("\(ttsManager.chunkLength) ký tự")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                } else if ttsManager.tool == "system" {
                    Stepper(value: $ttsManager.chunkLength, in: 50...500, step: 10) {
                        HStack {
                            Text("Độ dài phân đoạn (Siri):")
                            Spacer()
                            Text("\(ttsManager.chunkLength) ký tự")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                } else if ttsManager.tool == "vieneu" {
                    vieNeuPrefetchSection
                } else {
                    if currentExtParams.preloadSize == nil {
                        Stepper(value: $ttsManager.extPrefetchCount, in: 2...10) {
                            HStack {
                                Text("Số đoạn tải trước (Extension TTS):")
                                Spacer()
                                Text("\(ttsManager.extPrefetchCount) đoạn")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    if currentExtParams.maxLength == nil {
                        Stepper(value: $ttsManager.chunkLength, in: 50...500, step: 10) {
                            HStack {
                                Text("Độ dài đoạn văn (Extension TTS):")
                                Spacer()
                                Text("\(ttsManager.chunkLength) ký tự")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // `prefetchDelayMs` chi duoc tieu thu o duong worker (Google/extension) va
                // `TTSNextChapterPrefixSynthesizer` cho nhanh remote — engine local di thang
                // `localService.synthesize(...)` nen KHONG dung gia tri nay.
                if ttsManager.tool == "google" || TTSManager.isExtensionTool(ttsManager.tool) {
                    Stepper(value: $ttsManager.prefetchDelayMs, in: 300...5000, step: 50) {
                        HStack {
                            Text("Thời gian dãn tiến trình nạp trước:")
                            Spacer()
                            Text("\(ttsManager.prefetchDelayMs) ms")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }.glassSheetRows() }
        // Sheet (Widget TTS) ⇒ tiêu đề trái, đóng bằng vuốt xuống; đẩy từ Cài đặt ⇒ tiêu đề giữa.
        .pageTitle("Cài đặt TTS", style: isPresentedAsSheet ? .leading : .centered)
        .onAppear {
            // Phải đọc lại mỗi lần mở màn: `@State` chỉ khởi tạo một lần lúc View dựng ⇒ mở lại từ tab
            // Cài đặt hiện giá trị mặc định thay vì giá trị đã lưu (lỗi 1.3.456).
            refreshVieNeuSettings()
            // Tạm dừng phát để cấu hình — chỉ lần mở đầu; hiện lại sau trang con / đổi tab thì không (1.3.897).
            TTSSettingsPauseSession.begin()
            // Danh sách giọng của trình đọc do hàng "Giọng đọc" tự nạp (`TTSReaderVoiceSummaryRow`).
            if TTSManager.isExtensionTool(ttsManager.tool) {
                if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }) {
                    if ttsManager.extensionLocalPath != ext.localPath {
                        ttsManager.extensionLocalPath = ext.localPath
                    }
                    if ttsManager.extensionConfigJson != ext.configJson {
                        ttsManager.extensionConfigJson = ext.configJson
                    }
                }
            }
        }
        .onDisappear {
            // Chỉ cho **trang đẩy** ở tab Cài đặt: `isPresented` còn `true` ⇒ màn chỉ bị che (trang con, đổi tab), chưa
            // đóng ⇒ chưa đọc tiếp; `false` ⇒ bị gỡ khỏi stack ⇒ đọc tiếp (`TTSSettingsPauseSession`). Dạng **sheet** thì
            // vỏ `TTSSettingsSheet` báo kết thúc (1.3.907): ở màn gốc của sheet, `isPresented` không đáng tin lúc đóng.
            AppLogger.shared.log("[TTSSettings] onDisappear isPresented=\(isPresented) sheet=\(isPresentedAsSheet)")
            if !isPresentedAsSheet && !isPresented {
                TTSSettingsPauseSession.finish(caller: "TTSSettingsView.onDisappear")
            }
        }
        .onChange(of: ttsManager.tool) { _, newVal in
            if TTSManager.isExtensionTool(newVal) {
                if let ext = allExtensions.first(where: { $0.packageId == newVal }) {
                    ttsManager.extensionLocalPath = ext.localPath
                    ttsManager.extensionConfigJson = ext.configJson
                }
            } else {
                ttsManager.extensionLocalPath = ""
                ttsManager.extensionConfigJson = "{}"
            }
        }
        .sheet(item: $selectedExtForConfig, onDismiss: { MinimizedSourceCheckCoordinator.shared.screenDidClose(.script, screenId: nil) }) { ext in
            Group {
                ExtensionConfigView(ext: ext)
            }
            .appGlassSheet()
        }
        .vieNeuVoicePickerSheet(isPresented: $showingVieNeuVoicePicker)
        .ttsVoicePickerSheet(engine: $voicePickerEngine)
        .sheet(isPresented: $showingReplacementManagerSheet) {
            Group {
                NavigationStack { TTSReplacementManagerView(isPresentedAsSheet: true) }
                    .presentationDragIndicator(.visible)
            }
            .appGlassSheet()
        }
    }
}
