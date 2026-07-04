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
    @State private var showingFileImporter = false
    @State private var importType = "vietphrase"
    
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
                        HStack {
                            Text("Trạng thái từ điển")
                            Spacer()
                            if translationManager.isVietPhraseLoaded {
                                Text("Đã sẵn sàng")
                                    .foregroundColor(.green)
                            } else {
                                Text("Chưa có từ điển")
                                    .foregroundColor(.red)
                            }
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
                                }
                            }) {
                                Label(translationManager.isDownloaded() ? "Tải lại từ điển mặc định" : "Tải từ điển mặc định", systemImage: "arrow.down.circle")
                            }
                            
                            Menu {
                                Button("Nhập VietPhrase (.dat/.txt)") {
                                    importType = "vietphrase"
                                    showingFileImporter = true
                                }
                                Button("Nhập Names (.dat/.txt)") {
                                    importType = "names"
                                    showingFileImporter = true
                                }
                                Button("Nhập Phiên Âm (ChinesePhienAmWords.txt)") {
                                    importType = "phienam"
                                    showingFileImporter = true
                                }
                            } label: {
                                Label("Nhập từ điển tùy chỉnh...", systemImage: "plus.circle")
                            }
                        }
                        
                        Button(action: {
                            TranslateUtils.clearCache()
                        }) {
                            Label("Xóa cache dịch thuật", systemImage: "trash")
                        }
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
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.data, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let selectedUrl = urls.first else { return }
                    let accessing = selectedUrl.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            selectedUrl.stopAccessingSecurityScopedResource()
                        }
                    }
                    Task {
                        do {
                            try await translationManager.importDictionary(from: selectedUrl, type: importType)
                        } catch {
                            AppLogger.shared.log("❌ Lỗi import từ điển: \(error.localizedDescription)")
                        }
                    }
                case .failure(let error):
                    AppLogger.shared.log("❌ Lỗi chọn file: \(error.localizedDescription)")
                }
            }
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
}

#Preview {
    SettingsView()
}
