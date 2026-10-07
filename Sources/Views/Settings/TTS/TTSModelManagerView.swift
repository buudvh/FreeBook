import SwiftUI
import UniformTypeIdentifiers

struct TTSModelManagerView: View {
    @ObservedObject var ttsManager = TTSManager.shared
    /// Nguồn sự thật của tiến độ tải. **Không** giữ `@State` tiến độ ở đây nữa: `Task` tải không bị huỷ
    /// khi rời màn, nên trạng thái cục bộ mất trong khi việc tải vẫn chạy — đúng lỗi người dùng báo
    /// 2026-10-07 ("tải chưa xong thoát ra vào lại thì không thấy thanh tiến độ nữa").
    @ObservedObject private var downloads = ModelDownloadCenter.shared
    @State private var availableVoices: [Voice] = []
    @State private var isLoadingVoices = false
    @State private var isShowingFileImporter = false

    @State private var isImportingModel = false
    @State private var importModelMessage = "Đang nhập model..."
    @State private var modelRefreshTrigger = 0

    
    private func isModelDownloaded(_ voice: Voice) -> Bool {
        let _ = modelRefreshTrigger
        return (try? ModelStore().modelExists(for: voice.id)) ?? false
    }
    
    private var topVoices: [Voice] {
        let topNames = ["Ngọc Huyền (mới)", "Mai Phương", "Duy Onyx (mới)", "Ngọc Ngạn"].map { $0.precomposedStringWithCanonicalMapping }
        return NghiTTSClient.fallbackVietnameseVoices.filter { topNames.contains($0.name.precomposedStringWithCanonicalMapping) }
    }

    private var systemVoices: [Voice] {
        let _ = modelRefreshTrigger
        let topNames = ["Ngọc Huyền (mới)", "Mai Phương", "Duy Onyx (mới)", "Ngọc Ngạn"].map { $0.precomposedStringWithCanonicalMapping }
        let baseVoices = NghiTTSClient.fallbackVietnameseVoices.filter { !topNames.contains($0.name.precomposedStringWithCanonicalMapping) }
        
        let downloaded = baseVoices.filter { isModelDownloaded($0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let notDownloaded = baseVoices.filter { !isModelDownloaded($0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            
        return downloaded + notDownloaded
    }

    private var customVoices: [Voice] {
        let _ = modelRefreshTrigger
        guard let store = try? ModelStore() else { return [] }
        let localIDs = store.getLocalVoiceIDs()
        let fallbackIDs = NghiTTSClient.fallbackVietnameseVoices.map { $0.id }
        let customIDs = localIDs.filter { !fallbackIDs.contains($0) }
        let unsorted = customIDs.map { id in
            let name = id.replacingOccurrences(of: "_", with: " ").capitalized
            return Voice(id: id, name: name)
        }
        return unsorted.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            List {
                Section {
                    Button(action: {
                        isShowingFileImporter = true
                    }) {
                        Label("Nhập Model Ngoài...", systemImage: "square.and.arrow.down")
                            .foregroundColor(.white)
                    }
                }
                Section(header: HStack {
                    Text("Giọng đọc đặc sắc")
                    Spacer()
                    HStack(spacing: 12) {
                        Button("Tải tất cả") {
                            downloadAll(in: topVoices)
                        }
                        .buttonStyle(.borderless)
                        .textCase(.none)
                        .font(.caption)
                        .foregroundColor(.white)
                        Button("Xóa tất cả", role: .destructive) {
                            deleteAll(in: topVoices)
                        }
                        .buttonStyle(.borderless)
                        .textCase(.none)
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }) {
                    ForEach(topVoices) { voice in
                        modelRow(for: voice)
                    }
                }
                Section(header: HStack {
                    Text("Giọng đọc hệ thống")
                    Spacer()
                    HStack(spacing: 12) {
                        Button("Tải tất cả") {
                            downloadAll(in: systemVoices)
                        }
                        .buttonStyle(.borderless)
                        .textCase(.none)
                        .font(.caption)
                        .foregroundColor(.white)
                        
                        Button("Xóa tất cả", role: .destructive) {
                            deleteAll(in: systemVoices)
                        }
                        .buttonStyle(.borderless)
                        .textCase(.none)
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }) {
                    if isLoadingVoices {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        ForEach(systemVoices) { voice in
                            modelRow(for: voice)
                        }
                    }
                }
                
                let custom = customVoices
                if !custom.isEmpty {
                    Section(header: HStack {
                        Text("Giọng đọc tùy chỉnh")
                        Spacer()
                        Button("Xóa tất cả", role: .destructive) {
                            deleteAll(in: custom)
                        }
                        .buttonStyle(.borderless)
                        .textCase(.none)
                        .font(.caption)
                        .foregroundColor(.red)
                    }) {
                        ForEach(custom) { voice in
                            modelRow(for: voice, isCustom: true)
                        }
                    }
                }
            }
            .tint(.white)
            .navigationTitle("Quản lý Model")
            .background {
                DocumentPickerPresenter(
                    isPresented: $isShowingFileImporter,
                    allowedContentTypes: [UTType(filenameExtension: "onnx") ?? .data, .json],
                    allowsMultipleSelection: true,
                    onPick: { urls in
                        handleModelImportPick(urls: urls)
                    },
                    onCancel: nil
                )
            }
            .task {
                await loadVoices()
            }
            // Tải xong (hoặc lỗi) phải đọc lại đĩa: hàng giọng lấy dung lượng/trạng thái qua
            // `modelRefreshTrigger`, không bump thì vẫn hiện "Chưa tải về" dù file đã nằm trên máy.
            //
            // Theo dõi `isBusy` (Bool) chứ **không** theo dõi `entries`: `entries` đổi ở **mỗi nhịp** tiến
            // độ, bump theo nó là đọc lại dung lượng 20 giọng từ đĩa vài chục lần mỗi lượt tải.
            .onChange(of: downloads.isBusy) { _, _ in
                modelRefreshTrigger += 1
            }
            
            if isImportingModel {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                ProgressView(importModelMessage)
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
    }
    
    @ViewBuilder
    private func modelRow(for voice: Voice, isCustom: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(voice.name)
                    .font(.body)
                
                let isDownloaded = isModelDownloaded(voice)
                if isDownloaded {
                    if let store = try? ModelStore() {
                        let bytes = store.bytesForVoice(voice.id)
                        Text(String(format: "Dung lượng: %.1f MB", Double(bytes) / 1024.0 / 1024.0))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Chưa tải về")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let entry = downloadEntry(for: voice) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: entry.fraction)
                        Text(entry.message.isEmpty ? "Đang tải..." : entry.message)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            
            Spacer()
            
            if downloads.isRunning(id: ModelDownloadCenter.Target.nghiVoice(voice.id)) {
                ProgressView()
            } else {
                let isDownloaded = isModelDownloaded(voice)
                HStack(spacing: 8) {
                    if isDownloaded {
                        if !isCustom {
                            pillButton("Tải lại", color: .white) { downloadSingleModel(voice: voice) }
                        }
                        pillButton("Xóa", color: .red) { deleteSingleModel(voice: voice) }
                    } else {
                        pillButton("Tải", color: .white, isProminent: true) { downloadSingleModel(voice: voice) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Dòng tiến độ của giọng này, đọc từ `ModelDownloadCenter`. `nil` = không có lượt nào cho giọng đó.
    private func downloadEntry(for voice: Voice) -> ModelDownloadCenter.Entry? {
        downloads.entry(id: ModelDownloadCenter.Target.nghiVoice(voice.id))
    }

    private func pillButton(_ title: String, color: Color, isProminent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isProminent ? .semibold : .medium))
                .foregroundColor(color)
                .padding(.horizontal, isProminent ? 14 : 10)
                .padding(.vertical, 5)
                .background(color.opacity(isProminent ? 0.18 : 0.12))
                .overlay(Capsule().stroke(color.opacity(isProminent ? 0.35 : 0.25), lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private func loadVoices() async {
        isLoadingVoices = true
        defer { isLoadingVoices = false }
        availableVoices = (try? await ttsManager.nghiTTSClient?.getAllVoices(forceRefresh: false)) ?? NghiTTSClient.fallbackVietnameseVoices
    }
    
    /// Bàn giao cho `ModelDownloadCenter`: center giữ `Task`, tự chặn lượt trùng cho cùng một giọng, và tự
    /// phát kết quả qua `lastNotice` để `MainTabView` hiện toast. View không còn giữ trạng thái tải nào.
    private func downloadSingleModel(voice: Voice) {
        ModelDownloadCenter.shared.startNghiVoiceDownloads([voice])
    }
    
    private func deleteSingleModel(voice: Voice) {
        do {
            try ModelStore().deleteModel(for: voice.id)
            modelRefreshTrigger += 1
            ToastManager.shared.show(message: "Đã xóa model \(voice.name) thành công.", type: .success)
            if ttsManager.selectedVoice == voice.name {
                ttsManager.selectedVoice = ""
            }
            Task {
                await loadVoices()
            }
        } catch {
            ToastManager.shared.show(message: "Lỗi xóa model \(voice.name): \(error.localizedDescription)", type: .error)
        }
    }
    
    private func downloadAll(in list: [Voice]) {
        let toDownload = list.filter {
            !isModelDownloaded($0) && !downloads.isRunning(id: ModelDownloadCenter.Target.nghiVoice($0.id))
        }
        ModelDownloadCenter.shared.startNghiVoiceDownloads(toDownload)
    }
    
    private func deleteAll(in list: [Voice]) {
        let toDelete = list.filter { isModelDownloaded($0) }
        guard !toDelete.isEmpty else { return }
        for voice in toDelete {
            do {
                try ModelStore().deleteModel(for: voice.id)
                if ttsManager.selectedVoice == voice.name {
                    ttsManager.selectedVoice = ""
                }
            } catch {
                ToastManager.shared.show(message: "Lỗi xóa: \(error.localizedDescription)", type: .error)
            }
        }
        modelRefreshTrigger += 1
        Task {
            await loadVoices()
        }
    }
    

    
    private func handleModelImportPick(urls: [URL]) {
        isShowingFileImporter = false
        let validURLs = urls.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "onnx" || ext == "json"
        }
        if validURLs.isEmpty {
            ToastManager.shared.show(message: "Vui lòng chọn tệp tin model (.onnx) và cấu hình (.json).", type: .error)
            return
        }

        let onnxURLs = validURLs.filter { $0.pathExtension.lowercased() == "onnx" }
        let jsonURLs = validURLs.filter { $0.pathExtension.lowercased() == "json" }

        if onnxURLs.isEmpty || jsonURLs.isEmpty {
            ToastManager.shared.show(message: "Cần chọn cả hai tệp .onnx và .json cho model. Vui lòng thử lại.", type: .error)
            return
        }

        func cleanVoiceId(for url: URL) -> String {
            let baseName = url.deletingPathExtension().lastPathComponent
            if url.pathExtension.lowercased() == "json", baseName.lowercased().hasSuffix(".onnx") {
                return String(baseName.dropLast(5)).replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "", options: .regularExpression).lowercased()
            }
            return baseName.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "", options: .regularExpression).lowercased()
        }

        let jsonById = Dictionary(uniqueKeysWithValues: jsonURLs.compactMap { url in
            let id = cleanVoiceId(for: url)
            return id.isEmpty ? nil : (id, url)
        })

        var pairedFiles: [(onnxURL: URL, jsonURL: URL, voiceId: String)] = []
        var missingJSON: [String] = []
        for onnxURL in onnxURLs {
            let id = cleanVoiceId(for: onnxURL)
            if let jsonURL = jsonById[id] {
                pairedFiles.append((onnxURL: onnxURL, jsonURL: jsonURL, voiceId: id))
            } else {
                missingJSON.append(onnxURL.lastPathComponent)
            }
        }

        if !missingJSON.isEmpty {
            ToastManager.shared.show(message: "Thiếu tệp .json tương ứng cho: \(missingJSON.joined(separator: ", ")).", type: .error)
            return
        }

        isImportingModel = true
        importModelMessage = "Đang nhập model..."

        Task {
            let fm = FileManager.default
            var importCount = 0
            var errorCount = 0
            var lastErrorMessage: String?
            
            for pair in pairedFiles {
                let onnxAccess = pair.onnxURL.startAccessingSecurityScopedResource()
                let jsonAccess = pair.jsonURL.startAccessingSecurityScopedResource()
                
                defer {
                    if onnxAccess { pair.onnxURL.stopAccessingSecurityScopedResource() }
                    if jsonAccess { pair.jsonURL.stopAccessingSecurityScopedResource() }
                }
                
                guard let store = try? ModelStore() else { continue }
                let destOnnx = store.modelURL(for: pair.voiceId, extension: "onnx")
                let destConfig = store.modelURL(for: pair.voiceId, extension: "onnx.json")
                
                let targets = [
                    (source: pair.onnxURL, destination: destOnnx),
                    (source: pair.jsonURL, destination: destConfig)
                ]
                
                for target in targets {
                    var cleanupURL: URL?
                    do {
                        let values = try target.source.resourceValues(forKeys: [.fileSizeKey])
                        let size = values.fileSize ?? 0
                        if size <= 0 {
                            throw NSError(domain: "TTSModelManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tệp \(target.source.lastPathComponent) rỗng hoặc không đọc được."])
                        }
                        
                        if target.source.pathExtension.lowercased() == "json" {
                            let data = try Data(contentsOf: target.source)
                            _ = try JSONSerialization.jsonObject(with: data, options: [])
                        }
                        
                        if fm.fileExists(atPath: target.destination.path) {
                            try fm.removeItem(at: target.destination)
                        }
                        
                        cleanupURL = target.destination
                        try streamCopy(from: target.source, to: target.destination)
                        importCount += 1
                    } catch {
                        lastErrorMessage = error.localizedDescription
                        if let cleanup = cleanupURL, fm.fileExists(atPath: cleanup.path) {
                            try? fm.removeItem(at: cleanup)
                        }
                        errorCount += 1
                    }
                }
            }
            
            await MainActor.run {
                isImportingModel = false
                modelRefreshTrigger += 1
                if errorCount > 0 {
                    ToastManager.shared.show(message: lastErrorMessage ?? "Lỗi nhập model.", type: .error)
                } else {
                    ToastManager.shared.show(message: "Nhập thành công \(importCount / 2) model.", type: .success)
                }
                Task {
                    await loadVoices()
                }
            }
        }
    }
    
    private func streamCopy(from sourceURL: URL, to destinationURL: URL) throws {
        guard let inputStream = InputStream(url: sourceURL) else {
            throw NSError(domain: "StreamCopy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể mở input stream"])
        }
        guard let outputStream = OutputStream(url: destinationURL, append: false) else {
            throw NSError(domain: "StreamCopy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Không thể mở output stream"])
        }
        
        inputStream.open()
        defer { inputStream.close() }
        outputStream.open()
        defer { outputStream.close() }
        
        let bufferSize = 65536 // 64KB
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                if let error = inputStream.streamError {
                    throw error
                }
                throw NSError(domain: "StreamCopy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Lỗi đọc tệp nguồn"])
            } else if bytesRead == 0 {
                break
            }
            
            var bytesWritten = 0
            while bytesWritten < bytesRead {
                let written = outputStream.write(buffer.advanced(by: bytesWritten), maxLength: bytesRead - bytesWritten)
                if written < 0 {
                    if let error = outputStream.streamError {
                        throw error
                    }
                    throw NSError(domain: "StreamCopy", code: 4, userInfo: [NSLocalizedDescriptionKey: "Lỗi ghi tệp đích"])
                }
                bytesWritten += written
            }
        }
    }
}
