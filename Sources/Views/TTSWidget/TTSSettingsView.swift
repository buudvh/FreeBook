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
            Section("Công cụ đọc") {
                Picker("Trình đọc", selection: $ttsManager.tool) {
                    Text("Siri (Hệ thống Apple)").tag("system")
                    Text("NghiTTS (Piper Offline)").tag("nghitts")
                    Text("Chị Google (Trực tuyến)").tag("google")
                    ForEach(ttsExtensions) { ext in
                        Text(ext.name).tag(ext.packageId)
                    }
                }
                .pickerStyle(.menu)
            }
            
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
                    let hasNoModels = downloadedVoices.isEmpty
                    let missingDict = hasNoDictionary
                    
                    if hasNoModels || missingDict {
                        VStack(alignment: .leading, spacing: 10) {
                            if hasNoModels {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Chưa tải giọng đọc NghiTTS nào")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if missingDict {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Chưa tải thư viện phiên âm")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if hasNoModels {
                                NavigationLink(destination: TTSModelManagerView()) {
                                    Text("Tải model")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            if missingDict {
                                NavigationLink(destination: TTSDictionaryEditView()) {
                                    Text("Tải thư viện phiên âm")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            Picker("Giọng đọc NghiTTS", selection: $ttsManager.selectedVoice) {
                                ForEach(downloadedVoices, id: \.name) { voice in
                                    Text(voice.name)
                                        .tag(voice.name)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            NavigationLink(destination: TTSModelManagerView()) {
                                Label("Quản lý Model", systemImage: "waveform.and.mic")
                            }

                            NavigationLink(destination: TTSDictionaryEditView()) {
                                Label("Từ điển phiên âm cá nhân", systemImage: "character.book.closed")
                            }
                    } else if ttsManager.tool == "google" {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.blue)
                            Text("Giọng Tiếng Việt của Chị Google trực tuyến")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    } else {
                        // Trình đọc từ Extension
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
                
                if ttsManager.tool != "system" && ttsManager.tool != "nghitts" && ttsManager.tool != "google" {
                    if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }),
                       ExtensionManager.shared.hasConfig(localPath: ext.localPath) {
                        Section("Cấu hình") {
                            NavigationLink(destination: ExtensionConfigView(ext: ext)) {
                                Label("Cấu hình \(ext.name)", systemImage: "gearshape")
                            }
                        }
                    }
                }
                
                if ttsManager.tool == "nghitts" {
                    Section("NghiTTS (Piper Offline)") {
                        NavigationLink(destination: NghiTTSSettingsView()) {
                            Label("Cấu hình tiền xử lý & ngắt nghỉ", systemImage: "slider.horizontal.3")
                        }
                    }
                }
                
                Section("Cấu hình giọng nói") {
                    NavigationLink(destination: TTSReplacementManagerView()) {
                        Label("Quản lý thay thế ký tự", systemImage: "pencil.and.outline")
                    }
                    
                    VStack(alignment: .leading) {
                         HStack {
                             Text("Tốc độ:")
                             Spacer()
                             Text(String(format: "%.1fx", ttsManager.speed))
                                 .font(.system(.body, design: .monospaced))
                         }
                         Slider(value: $ttsManager.speed, in: 0.5...5.0, step: 0.1)
                    }
                    
                    VStack(alignment: .leading) {
                         HStack {
                             Text("Cao độ (Pitch):")
                             Spacer()
                             Text(String(format: "%.1fx", ttsManager.pitch))
                                 .font(.system(.body, design: .monospaced))
                         }
                         Slider(value: $ttsManager.pitch, in: 0.5...2.0, step: 0.1)
                             .disabled(ttsManager.tool == "nghitts")
                         if ttsManager.tool == "nghitts" {
                             Text("(*) NghiTTS không hỗ trợ chỉnh cao độ thời gian thực")
                                 .font(.caption2)
                                 .foregroundColor(.secondary)
                         }
                    }
                    
                    HStack {
                        Text("Độ dài phân đoạn (ký tự)")
                        Spacer()
                        TextField("200", value: $ttsManager.chunkLength, formatter: NumberFormatter())
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
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
                // Tạm dừng phát để cấu hình
                ttsManager.prepareForSettings()
                
                self.systemVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("vi") }
                
                if ttsManager.tool == "system" && ttsManager.selectedVoice.isEmpty {
                    ttsManager.selectedVoice = systemVoices.first?.identifier ?? ""
                }
                
                if ttsManager.tool != "system" && ttsManager.tool != "nghitts" {
                    if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }) {
                        ttsManager.extensionLocalPath = ext.localPath
                        ttsManager.extensionConfigJson = ext.configJson
                    }
                    loadExtensionVoices(packageId: ttsManager.tool)
                }
                
                Task {
                    self.availableVoices = (try? await ttsManager.nghiTTSClient?.getAllVoices(forceRefresh: false)) ?? NghiTTSClient.fallbackVietnameseVoices
                }
            }
            .onDisappear {
                // Chỉ lưu và khôi phục khi View thực sự bị đóng/pop hoàn toàn khỏi stack
                if !presentationMode.wrappedValue.isPresented {
                    // 1. Tự động lưu cấu hình extension
                    if ttsManager.tool != "system" && ttsManager.tool != "nghitts" {
                        if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }) {
                            ttsManager.extensionConfigJson = ext.configJson
                        }
                    }
                    
                    // 2. Tiếp tục phát truyện ngay tại đoạn dở dang với cấu hình mới
                    ttsManager.resumeAfterSettings()
                }
            }
            .onChange(of: ttsManager.tool) { _, newVal in
                if newVal != "system" && newVal != "nghitts" {
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
