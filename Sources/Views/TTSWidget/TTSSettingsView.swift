import SwiftUI
import SwiftData
import AVFoundation

struct TTSSettingsView: View {
    let isPresentedAsSheet: Bool
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var ttsManager = TTSManager.shared
    @State private var availableVoices: [Voice] = []
    @State private var systemVoices: [AVSpeechSynthesisVoice] = []
    
    @Query private var allExtensions: [Extension]
    
    private var ttsExtensions: [Extension] {
        allExtensions.filter { $0.type == "tts" && !$0.localPath.isEmpty && $0.isEnabled }
    }
    
    @State private var extensionVoices: [[String: String]] = []
    @State private var isLoadingVoices = false
    @State private var selectedExtForConfig: Extension? = nil
    @State private var showingReplacementManagerSheet = false
    @AppStorage("google_cloud_tts_custom_api_key") private var customGoogleApiKey: String = ""
    @State private var showApiKey: Bool = false
    @State private var hasResumed = false
    
    private var currentExtParams: (preloadSize: Int?, maxLength: Int?) {
        let path = allExtensions.first(where: { $0.packageId == ttsManager.tool })?.localPath ?? ttsManager.extensionLocalPath
        return ttsManager.parseExtensionConfigParams(jsonString: ttsManager.extensionConfigJson, localPath: path)
    }

    private var hasNoDictionary: Bool {
        let path = (try? ModelStore())?.rootURL.appendingPathComponent("non-vietnamese-words.plist").path ?? ""
        return !FileManager.default.fileExists(atPath: path)
    }
    
    private func loadExtensionVoices(packageId: String) {
        guard let ext = allExtensions.first(where: { $0.packageId == packageId }) else { return }
        isLoadingVoices = true
        Task {
            do {
                let voices = try await ExtensionManager.shared.ttsVoices(
                    localPath: ext.localPath,
                    downloadUrl: ext.downloadUrl,
                    configJson: ext.configJson
                )
                await MainActor.run {
                    self.extensionVoices = voices
                    self.isLoadingVoices = false
                    
                    let voiceIds = voices.compactMap { $0["id"] }
                    if !voiceIds.contains(ttsManager.selectedVoice) {
                        if let firstVoice = voiceIds.first {
                            ttsManager.selectedVoice = firstVoice
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.extensionVoices = []
                    self.isLoadingVoices = false
                }
            }
        }
    }
    
    var body: some View {
        Form {
            // Section 1: Chọn trình đọc
            Section("Trình đọc") {
                Picker("Trình đọc", selection: $ttsManager.tool) {
                    Text("Siri (Hệ thống Apple)").tag("system")
                    Text("NghiTTS (Piper Offline)").tag("nghitts")
                    Text("Google Cloud TTS (Online)").tag("google")
                    ForEach(ttsExtensions) { ext in
                        Text(ext.name).tag(ext.packageId)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Section 2: Chọn giọng đọc
            Section("Giọng đọc") {
                if ttsManager.tool == "system" {
                    Picker("Giọng đọc Siri", selection: $ttsManager.selectedVoice) {
                        ForEach(systemVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.quality == .premium ? "Premium" : "Default"))")
                                .tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                } else if ttsManager.tool == "nghitts" {
                    let downloadedVoices = availableVoices.filter { isModelDownloaded($0) }
                    if downloadedVoices.isEmpty {
                        Text("Chưa tải giọng đọc NghiTTS nào")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Giọng đọc NghiTTS", selection: $ttsManager.selectedVoice) {
                            ForEach(downloadedVoices, id: \.name) { voice in
                                Text(voice.name).tag(voice.name)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } else if ttsManager.tool == "google" {
                    Picker("Giọng đọc Google TTS", selection: $ttsManager.selectedVoice) {
                        ForEach(GoogleVoice.allVoices) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    if isLoadingVoices {
                        ProgressView("Đang tải giọng đọc...")
                    } else if extensionVoices.isEmpty {
                        Text("Không có giọng đọc nào")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Giọng đọc Extension", selection: $ttsManager.selectedVoice) {
                            ForEach(0..<extensionVoices.count, id: \.self) { idx in
                                let voice = extensionVoices[idx]
                                let id = voice["id"] ?? ""
                                let name = voice["name"] ?? id
                                let lang = voice["language"] ?? ""
                                Text("\(name) (\(lang))").tag(id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            // Section 3: Quản lý riêng của trình đọc
            Section("Quản lý riêng của trình đọc") {
                if ttsManager.tool == "google" {
                    HStack {
                        Text("Trạng thái Key hệ thống:")
                        Spacer()
                        if GoogleTTSService.shared.hasApiKey {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text("Đã sẵn sàng").font(.caption).foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                Text("Chưa có Key").font(.caption).foregroundColor(.red)
                            }
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
                                    .disableAutocorrection(true)
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
                    let downloadedVoices = availableVoices.filter { isModelDownloaded($0) }
                    let hasNoModels = downloadedVoices.isEmpty
                    let missingDict = hasNoDictionary

                    if hasNoModels || missingDict {
                        VStack(alignment: .leading, spacing: 6) {
                            if hasNoModels {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                    Text("Chưa tải giọng đọc NghiTTS nào").font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                            if missingDict {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                    Text("Chưa tải thư viện phiên âm").font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    NavigationLink(destination: TTSModelManagerView()) {
                        Label("Quản lý Model giọng đọc", systemImage: "waveform.and.mic")
                    }
                    NavigationLink(destination: NghiTTSSettingsView()) {
                        Label("Cấu hình tiền xử lý & ngắt nghỉ", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink(destination: TTSDictionaryEditView()) {
                        Label("Từ điển phiên âm cá nhân", systemImage: "character.book.closed")
                    }
                } else if ttsManager.tool != "system" {
                    if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }) {
                        Button(action: { self.selectedExtForConfig = ext }) {
                            HStack {
                                Image(systemName: "slider.horizontal.3").foregroundColor(.accentColor)
                                Text("Cấu hình Extension (\(ext.name))").foregroundColor(.accentColor)
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
            }

            // Section 4: Cấu hình giọng nói
            Section(header: HStack {
                Text("Cấu hình giọng nói")
                Spacer()
                Button(action: {
                    ttsManager.speed = 1.0
                    ttsManager.pitch = 1.0
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Đặt lại")
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
            }) {
                Button(action: { showingReplacementManagerSheet = true }) {
                    HStack {
                        Label("Quản lý thay thế ký tự", systemImage: "pencil.and.outline")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: $ttsManager.speed, in: 0.5...5.0, step: 0.1) {
                        HStack {
                            Text("Tốc độ:")
                            Spacer()
                            Text(String(format: "%.1fx", ttsManager.speed))
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    Slider(value: $ttsManager.speed, in: 0.5...5.0, step: 0.1)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: $ttsManager.pitch, in: 0.5...2.0, step: 0.1) {
                        HStack {
                            Text("Cao độ (Pitch):")
                            Spacer()
                            Text(String(format: "%.1fx", ttsManager.pitch))
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .disabled(ttsManager.tool == "nghitts")

                    Slider(value: $ttsManager.pitch, in: 0.5...2.0, step: 0.1)
                        .disabled(ttsManager.tool == "nghitts")
                    if ttsManager.tool == "nghitts" {
                        Text("(*) NghiTTS không hỗ trợ chỉnh cao độ thời gian thực")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Section 5: Tải trước dữ liệu
            Section(header: HStack {
                Text("Tải trước dữ liệu")
                Spacer()
                Button(action: {
                    if ttsManager.tool == "google" {
                        ttsManager.googlePrefetchCount = 2
                        ttsManager.chunkLength = 100
                        ttsManager.prefetchDelayMs = 350
                    } else if ttsManager.tool == "nghitts" || ttsManager.tool == "system" {
                        ttsManager.chunkLength = 100
                        ttsManager.prefetchDelayMs = 350
                    } else {
                        ttsManager.extPrefetchCount = 2
                        ttsManager.chunkLength = 100
                        ttsManager.prefetchDelayMs = 350
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Đặt lại")
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
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
                        HStack {
                            Text("Bộ đệm âm thanh (NghiTTS):")
                            Spacer()
                            Text("\(String(format: "%.1f", ttsManager.nghiBufferedDuration))s / \(String(format: "%.0f", ttsManager.nghiWatermarks.high))s")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.accentColor)
                        }
                        Text("Tự động ngắt nạp khi đệm đủ thời lượng để tiết kiệm pin & hạ nhiệt máy.")
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

                if ttsManager.tool != "system" {
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
        }
        .navigationTitle("Cài đặt TTS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPresentedAsSheet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            self.hasResumed = false
            // Tạm dừng phát để cấu hình
            ttsManager.prepareForSettings()
            
            self.systemVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("vi") }
            
            if ttsManager.tool == "system" && ttsManager.selectedVoice.isEmpty {
                ttsManager.selectedVoice = systemVoices.first?.identifier ?? ""
            }
            
            if ttsManager.tool != "system" && ttsManager.tool != "nghitts" && ttsManager.tool != "google" {
                if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }) {
                    if ttsManager.extensionLocalPath != ext.localPath {
                        ttsManager.extensionLocalPath = ext.localPath
                    }
                    if ttsManager.extensionConfigJson != ext.configJson {
                        ttsManager.extensionConfigJson = ext.configJson
                    }
                }
                loadExtensionVoices(packageId: ttsManager.tool)
            }
            
            Task {
                self.availableVoices = (try? await ttsManager.nghiTTSClient?.getAllVoices(forceRefresh: false)) ?? NghiTTSClient.fallbackVietnameseVoices
            }
        }
        .onDisappear {
            if !hasResumed {
                hasResumed = true
                // 1. Tự động lưu cấu hình extension (nếu có thay đổi)
                if ttsManager.tool != "system" && ttsManager.tool != "nghitts" && ttsManager.tool != "google" {
                    if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }),
                       ttsManager.extensionConfigJson != ext.configJson {
                        ttsManager.extensionConfigJson = ext.configJson
                    }
                }
                
                // 2. Tiếp tục phát truyện ngay tại đoạn dở dang với cấu hình mới
                ttsManager.resumeAfterSettings()
            }
        }
        .onChange(of: ttsManager.tool) { _, newVal in
            if newVal != "system" && newVal != "nghitts" && newVal != "google" {
                if let ext = allExtensions.first(where: { $0.packageId == newVal }) {
                    ttsManager.extensionLocalPath = ext.localPath
                    ttsManager.extensionConfigJson = ext.configJson
                }
                loadExtensionVoices(packageId: newVal)
            } else {
                ttsManager.extensionLocalPath = ""
                ttsManager.extensionConfigJson = "{}"
            }
        }
        .sheet(item: $selectedExtForConfig) { ext in
            ExtensionConfigView(ext: ext)
        }
        .sheet(isPresented: $showingReplacementManagerSheet) {
            NavigationStack {
                TTSReplacementManagerView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Đóng") {
                                showingReplacementManagerSheet = false
                            }
                        }
                    }
            }
        }
    }
    
    private func isModelDownloaded(_ voice: Voice) -> Bool {
        return (try? ModelStore().modelExists(for: voice.id)) ?? false
    }
    
    private func deleteModel(_ voice: Voice) {
        try? ModelStore().deleteModel(for: voice.id)
        if ttsManager.selectedVoice == voice.name {
            ttsManager.selectedVoice = ""
        }
        Task {
            self.availableVoices = (try? await ttsManager.nghiTTSClient?.getAllVoices(forceRefresh: false)) ?? NghiTTSClient.fallbackVietnameseVoices
        }
    }
}
