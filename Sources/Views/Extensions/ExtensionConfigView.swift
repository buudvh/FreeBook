import SwiftUI
import SwiftData

struct ExtensionConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var ext: Extension
    
    // Lưu các cấu hình định nghĩa trong plugin.json
    @State private var configDefinitions: [String: ConfigItem] = [:]
    // Lưu các giá trị hiện tại người dùng nhập vào
    @State private var userValues: [String: String] = [:]
    
    @State private var isLoading = true
    @State private var errorMessage = ""
    
    struct ConfigItem: Codable {
        let title: String?
        let mode: String?
        let format: String?
        let `default`: String?
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Đang đọc cấu hình...")
                } else if !errorMessage.isEmpty {
                    VStack(spacing: 16) {
                        Text("Lỗi đọc cấu hình")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                        Button("Hủy") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                } else if configDefinitions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.green)
                        Text("Tiện ích '\(ext.name)' không có cấu hình bổ sung.")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Button("Đóng") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    Form {
                        Section(header: Text("Tùy Chỉnh Biến Global")) {
                            ForEach(Array(configDefinitions.keys).sorted(), id: \.self) { key in
                                let definition = configDefinitions[key]!
                                let title = definition.title ?? key
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    
                                    // Hiển thị Input tùy theo định dạng
                                    if definition.format == "boolean" || definition.mode == "toggle" {
                                        Toggle(isOn: Binding(
                                            get: { (userValues[key] ?? definition.default ?? "false") == "true" },
                                            set: { userValues[key] = $0 ? "true" : "false" }
                                        )) {
                                            Text(key)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        TextField(definition.default ?? "", text: Binding(
                                            get: { userValues[key] ?? "" },
                                            set: { userValues[key] = $0 }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.none)
                                    }
                                    
                                    if let defaultVal = definition.default {
                                        Text("Mặc định: \(defaultVal)")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cấu Hình: \(ext.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !configDefinitions.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Hủy") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lưu") {
                            saveConfig()
                        }
                    }
                }
            }
            .onAppear {
                loadConfigDefinitions()
            }
        }
    }
    
    private func loadConfigDefinitions() {
        guard !ext.localPath.isEmpty else {
            errorMessage = "Tiện ích chưa được cài đặt cục bộ."
            isLoading = false
            return
        }
        
        let extUrl = URL(fileURLWithPath: ext.localPath)
        let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")
        
        guard FileManager.default.fileExists(atPath: pluginJsonUrl.path) else {
            errorMessage = "Không tìm thấy tệp plugin.json"
            isLoading = false
            return
        }
        
        do {
            let data = try Data(contentsOf: pluginJsonUrl)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let configSection = json["config"] as? [String: Any] {
                
                var definitions: [String: ConfigItem] = [:]
                for (key, value) in configSection {
                    if let dict = value as? [String: Any] {
                        if let dictData = try? JSONSerialization.data(withJSONObject: dict),
                           let item = try? JSONDecoder().decode(ConfigItem.self, from: dictData) {
                            definitions[key] = item
                        }
                    }
                }
                self.configDefinitions = definitions
            }
            
            // Đọc các giá trị người dùng đã lưu trước đó trong Extension
            if let userConfigData = ext.configJson.data(using: .utf8),
               let savedValues = try? JSONSerialization.jsonObject(with: userConfigData) as? [String: String] {
                self.userValues = savedValues
            }
            
            // Điền sẵn các giá trị mặc định cho những key chưa được lưu
            for (key, definition) in configDefinitions {
                if userValues[key] == nil {
                    userValues[key] = definition.default ?? ""
                }
            }
            
            isLoading = false
        } catch {
            errorMessage = "Lỗi xử lý file plugin.json: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func saveConfig() {
        do {
            // Lọc bỏ các giá trị trống để tiết kiệm dung lượng
            let filteredValues = userValues.filter { !$0.value.isEmpty }
            
            let data = try JSONSerialization.data(withJSONObject: filteredValues, options: [])
            if let jsonString = String(data: data, encoding: .utf8) {
                ext.configJson = jsonString
                try? modelContext.save()
            }
            dismiss()
        } catch {
            // print("Lỗi lưu cấu hình: \(error.localizedDescription)")
        }
    }
}
