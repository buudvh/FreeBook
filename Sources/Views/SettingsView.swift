import SwiftUI

struct SettingsView: View {
    @AppStorage("isLoggingEnabled") private var isLoggingEnabled = true
    
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
        }
    }
}

#Preview {
    SettingsView()
}
