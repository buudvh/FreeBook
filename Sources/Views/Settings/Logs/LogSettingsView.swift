import SwiftUI

/// Màn "Ghi log hệ thống" (Cài đặt → Nhà Phát Triển). Công tắc, 3 nút và 3 alert chuyển **nguyên văn** từ
/// `SettingsView` (1.3.520); thêm dòng số file descriptor đang mở (`FileDescriptorCensus.openCount()`) và
/// danh sách file log (chỉ xem).
struct LogSettingsView: View {
    private struct LogFileRow: Identifiable {
        let url: URL
        let size: UInt64
        let modified: Date?
        var id: URL { url }
    }

    @AppStorage("isLoggingEnabled") private var isLoggingEnabled = false
    @AppStorage("isCompactSuccessLogEnabled") private var isCompactSuccessLogEnabled = true
    @AppStorage("isTTSVerboseLoggingEnabled") private var isTTSVerboseLoggingEnabled = false

    @State private var logFileURLs: [URL] = [] // giữ trong state để mở lại màn hình là thấy file mới chia
    @State private var logFiles: [LogFileRow] = []
    @State private var openFileCount: Int = 0
    @State private var openFileLimit: Int = 0
    @State private var showingCopyWarningAlert = false
    @State private var showingCopySuccessAlert = false
    @State private var showingClearLogAlert = false

    var body: some View {
        Form {
            Section(header: Text("Cấu Hình")) {
                Toggle(isOn: $isLoggingEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ghi log hệ thống")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Bật ghi log giúp chẩn đoán và sửa lỗi. Dòng lỗi (❌) luôn được ghi.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: isLoggingEnabled) { _, newValue in
                    AppLogger.shared.isLoggingEnabled = newValue
                }

                if isLoggingEnabled {
                    Toggle(isOn: $isCompactSuccessLogEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Thu gọn log kết quả Extension")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Rút gọn dữ liệu trả về của extension trong log để tiết kiệm dung lượng đĩa.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 16)
                    .onChange(of: isCompactSuccessLogEnabled) { _, newValue in
                        AppLogger.shared.isCompactSuccessLogEnabled = newValue
                    }

                    Toggle(isOn: $isTTSVerboseLoggingEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ghi log TTS chi tiết")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Ghi log chi tiết từng chunk, highlight và tham số TTS (có thể giảm hiệu năng).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 16)
                    .onChange(of: isTTSVerboseLoggingEnabled) { _, newValue in
                        AppLogger.shared.isTTSVerboseLoggingEnabled = newValue
                    }
                }
            }

            Section(header: Text("Chẩn Đoán")) {
                LabeledContent("File đang mở", value: "\(openFileCount) / \(openFileLimit)")
            }

            Section {
                if logFiles.isEmpty {
                    Text("Chưa có dữ liệu log ghi nhận.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(logFiles) { file in
                        LabeledContent {
                            Text(formatBytes(file.size))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.url.lastPathComponent)
                                Text(fileSubtitle(file))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("File Log")
            } footer: {
                Text("Mỗi file quá 2 MB tự chia sang app_logs.1…4.txt; file cũ nhất bị xoá.")
            }

            if !logFileURLs.isEmpty {
                Section(header: Text("Thao Tác")) {
                    Button(action: {
                        let fileSize = AppLogger.shared.logFileSize
                        if fileSize > 1 * 1024 * 1024 { // > 1MB
                            showingCopyWarningAlert = true
                        } else {
                            copyLogToClipboard()
                        }
                    }) {
                        Label("Sao chép nhật ký log (file mới nhất)", systemImage: "doc.on.doc")
                    }

                    ShareLink(items: logFileURLs) {
                        Label("Xuất tất cả file log", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive, action: {
                        showingClearLogAlert = true
                    }) {
                        Label("Xóa tất cả nhật ký log", systemImage: "trash")
                    }
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
        .navigationTitle("Ghi log hệ thống")
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
            Text("Đã sao chép file log mới nhất vào bộ nhớ tạm.")
        }
        .alert("Xóa Nhật Ký", isPresented: $showingClearLogAlert) {
            Button("Hủy", role: .cancel) {}
            Button("Xóa", role: .destructive) {
                AppLogger.shared.clear()
                updateLogStatus()
            }
        } message: {
            Text("Bạn có chắc chắn muốn xóa tất cả file log (app_logs*.txt) không? Thao tác này không thể hoàn tác.")
        }
    }

    private func updateLogStatus() {
        logFileURLs = AppLogger.shared.logFileUrls()
        logFiles = logFileURLs.map { url in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return LogFileRow(
                url: url,
                size: (attributes?[.size] as? UInt64) ?? 0,
                modified: attributes?[.modificationDate] as? Date
            )
        }
        let counts = FileDescriptorCensus.openCount()
        openFileCount = counts.open
        openFileLimit = counts.limit
    }

    private func fileSubtitle(_ file: LogFileRow) -> String {
        let time = file.modified.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—"
        return file.url == AppLogger.shared.getLogFileUrl() ? "Đang ghi · \(time)" : time
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
