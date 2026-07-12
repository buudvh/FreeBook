import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("isLoggingEnabled") private var isLoggingEnabled = true
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @ObservedObject private var translationManager = TranslationManager.shared
    
    @State private var logFileExists = false
    @State private var showingCopyWarningAlert = false
    @State private var showingCopySuccessAlert = false
    @State private var showingClearLogAlert = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var showingFileImporter = false
    @State private var importType = "vietphrase"
    @State private var importingTypes: Set<String> = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Hệ Thống")) {
                    Toggle(isOn: $isLoggingEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ghi log hệ thống")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Bật ghi log giúp chẩn đoán và sửa lỗi của các VBook extension. Log được lưu trong file app_logs.txt trên thiết bị.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: isLoggingEnabled) { _, newValue in
                        AppLogger.shared.isLoggingEnabled = newValue
                    }
                }
                
                Section(header: Text("Dịch Thuật Quick Translate")) {
                    Toggle(isOn: $isTranslationEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bật dịch Quick Translate")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Tự động dịch siêu dữ liệu và nội dung truyện chữ tiếng Trung sang tiếng Việt (Hán-Việt/VietPhrase).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: isTranslationEnabled) { _, newValue in
                        TranslateUtils.clearCache()
                    }
                    
                    if isTranslationEnabled {
                        Section(header: Text("Từ điển chung")) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                Button(action: {
                                    importType = "vietphrase"
                                    showingFileImporter = true
                                }) {
                                    DictionaryCard(
                                        title: "VietPhrase.txt",
                                        statusText: getStatusText(for: "vietphrase"),
                                        isSet: translationManager.isVietPhraseLoaded,
                                        isLoading: importingTypes.contains("vietphrase")
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(importingTypes.contains("vietphrase"))
                                
                                Button(action: {
                                    importType = "names"
                                    showingFileImporter = true
                                }) {
                                    DictionaryCard(
                                        title: "Name.txt",
                                        statusText: getStatusText(for: "names"),
                                        isSet: translationManager.isNamesLoaded,
                                        isLoading: importingTypes.contains("names")
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(importingTypes.contains("names"))
                                
                                Button(action: {
                                    importType = "phienam"
                                    showingFileImporter = true
                                }) {
                                    DictionaryCard(
                                        title: "PhienAm.txt",
                                        statusText: getStatusText(for: "phienam"),
                                        isSet: translationManager.isPhienAmLoaded,
                                        isLoading: importingTypes.contains("phienam")
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(importingTypes.contains("phienam"))
                                
                                Button(action: {
                                    importType = "pronouns"
                                    showingFileImporter = true
                                }) {
                                    DictionaryCard(
                                        title: "Pronouns.txt",
                                        statusText: getStatusText(for: "pronouns"),
                                        isSet: translationManager.isPronounsLoaded,
                                        isLoading: importingTypes.contains("pronouns")
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(importingTypes.contains("pronouns"))
                                
                                Button(action: {
                                    importType = "luatnhan"
                                    showingFileImporter = true
                                }) {
                                    DictionaryCard(
                                        title: "LuatNhan.txt",
                                        statusText: getStatusText(for: "luatnhan"),
                                        isSet: translationManager.isLuatNhanLoaded,
                                        isLoading: importingTypes.contains("luatnhan")
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(importingTypes.contains("luatnhan"))
                            }
                            .padding(.vertical, 4)
                        }
                        
                        if translationManager.isDownloading {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(translationManager.downloadMessage)
                                    .font(.caption)
                                ProgressView(value: translationManager.downloadProgress)
                            }
                        } else {
                            Button(action: {
                                Task {
                                    await translationManager.downloadDefaultDictionaries()
                                    await MainActor.run {
                                        DictionaryCache.shared.invalidateAll()
                                    }
                                }
                            }) {
                                Label(translationManager.isDownloaded() ? "Tải lại từ điển mặc định" : "Tải từ điển mặc định", systemImage: "arrow.down.circle")
                            }
                            .disabled(!importingTypes.isEmpty)
                        }
                        
                        Button(action: {
                            importingTypes.insert("refresh")
                            Task {
                                do {
                                    try await translationManager.loadAllDictionaries()
                                    translationManager.clearBookDictCache()
                                    TranslateUtils.clearCache()
                                    await MainActor.run {
                                        DictionaryCache.shared.invalidateAll()
                                        importingTypes.remove("refresh")
                                        showToast("Đã làm mới dữ liệu dịch thành công")
                                    }
                                } catch {
                                    await MainActor.run {
                                        importingTypes.remove("refresh")
                                        showToast("Lỗi làm mới dữ liệu dịch: \(error.localizedDescription)")
                                    }
                                }
                            }
                        }) {
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
                }
                
                Section(header: Text("Đọc Thành Tiếng (TTS)")) {
                    NavigationLink(destination: TTSSettingsView(isPresentedAsSheet: false)) {
                        Label("Cài đặt TTS", systemImage: "waveform")
                    }
                    NavigationLink(destination: TTSModelManagerView()) {
                        Label("Quản lý Model", systemImage: "waveform.and.mic")
                    }
                    NavigationLink(destination: TTSDictionaryEditView()) {
                        Label("Từ điển phiên âm cá nhân", systemImage: "character.book.closed")
                    }
                    NavigationLink(destination: NghiTTSSettingsView()) {
                        Label("Cấu hình tiền xử lý & ngắt nghỉ", systemImage: "slider.horizontal.3")
                    }
                }
                
                Section(header: Text("Nhật Ký (Log)")) {
                    if logFileExists {
                        Button(action: {
                            let fileSize = AppLogger.shared.logFileSize
                            if fileSize > 1 * 1024 * 1024 { // > 1MB
                                showingCopyWarningAlert = true
                            } else {
                                copyLogToClipboard()
                            }
                        }) {
                            Label("Sao chép nhật ký log", systemImage: "doc.on.doc")
                        }
                        
                        ShareLink(item: AppLogger.shared.getLogFileUrl()) {
                            Label("Xuất file log (app_logs.txt)", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive, action: {
                            showingClearLogAlert = true
                        }) {
                            Label("Xóa nhật ký log", systemImage: "trash")
                        }
                    } else {
                        Text("Chưa có dữ liệu log ghi nhận.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Thông Tin")) {
                    HStack {
                        Text("Phiên bản ứng dụng")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Cài Đặt")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                updateLogStatus()
            }
            .alert("Log File Quá Lớn", isPresented: $showingCopyWarningAlert) {
                Button("Hủy", role: .cancel) {}
                Button("Vẫn sao chép", role: .none) {
                    copyLogToClipboard()
                }
            } message: {
                Text("Kích thước file log là \(formatBytes(AppLogger.shared.logFileSize)). Việc sao chép file lớn có thể gây chậm hoặc đơ thiết bị. Bạn có chắc chắn muốn tiếp tục?")
            }
            .alert("Đã Sao Chép", isPresented: $showingCopySuccessAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Đã sao chép toàn bộ nhật ký log vào bộ nhớ tạm.")
            }
            .alert("Xóa Nhật Ký", isPresented: $showingClearLogAlert) {
                Button("Hủy", role: .cancel) {}
                Button("Xóa", role: .destructive) {
                    AppLogger.shared.clear()
                    updateLogStatus()
                }
            } message: {
                Text("Bạn có chắc chắn muốn xóa file app_logs.txt không? Thao tác này không thể hoàn tác.")
            }
            .overlay(alignment: .bottom) {
                if showingToast {
                    Text(toastMessage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.1, green: 0.1, blue: 0.1).opacity(0.92))
                                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                        )
                        .padding(.bottom, 70)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(
                DocumentPickerPresenter(
                    isPresented: $showingFileImporter,
                    allowedContentTypes: [.plainText, .text],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        guard let selectedUrl = urls.first else { return }
                        let accessing = selectedUrl.startAccessingSecurityScopedResource()
                        defer {
                            if accessing {
                                selectedUrl.stopAccessingSecurityScopedResource()
                            }
                        }
                        
                        let currentType = importType
                        importingTypes.insert(currentType)
                        
                        Task {
                            do {
                                try await translationManager.importDictionary(from: selectedUrl, type: currentType)
                                await MainActor.run {
                                    // Invalidate DictionaryCache so it reloads from new .dat
                                    if currentType == "vietphrase" {
                                        DictionaryCache.shared.invalidate(type: .vietPhrase)
                                    } else if currentType == "names" {
                                        DictionaryCache.shared.invalidate(type: .names)
                                    }
                                    showToast("Nhập dữ liệu từ điển thành công!")
                                }
                            } catch {
                                AppLogger.shared.log("❌ Lỗi import từ điển: \(error.localizedDescription)")
                                await MainActor.run {
                                    showToast("Lỗi: \(error.localizedDescription)")
                                }
                            }
                            _ = await MainActor.run {
                                importingTypes.remove(currentType)
                            }
                        }
                    },
                    onCancel: nil
                )
            )
        }
    }
    
    private func updateLogStatus() {
        logFileExists = FileManager.default.fileExists(atPath: AppLogger.shared.getLogFileUrl().path)
    }
    
    private func copyLogToClipboard() {
        let contents = AppLogger.shared.readLogContents()
        UIPasteboard.general.string = contents
        showingCopySuccessAlert = true
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func getStatusText(for type: String) -> String {
        if importingTypes.contains(type) {
            return "Đang import..."
        }
        if let count = translationManager.getWordCount(for: type) {
            return "\(count) từ"
        }
        return "<Chưa thiết lập>"
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            showingToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showingToast = false
                }
            }
        }
    }
}

// MARK: - Dictionary Status Card Subview

struct DictionaryCard: View {
    let title: String
    let statusText: String
    let isSet: Bool
    let isLoading: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(isLoading ? .blue : (isSet ? .secondary : .red))
                    .lineLimit(1)
            }
            
            if isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

#Preview {
    SettingsView()
}
