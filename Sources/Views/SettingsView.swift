import SwiftUI

struct SettingsView: View {
    @AppStorage("isLoggingEnabled") private var isLoggingEnabled = true
    @State private var logFileExists = false
    @State private var showingCopyWarningAlert = false
    @State private var showingCopySuccessAlert = false
    @State private var showingClearLogAlert = false
    
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
