import SwiftUI
import SwiftData

struct ExtensionStoreView: View {
    @Environment(\.modelContext) private var modelContext
    var repository: Repository
    
    @State private var loadingStates: [String: Bool] = [:] // packageId: isDownloading
    @State private var errorMessage = ""
    @State private var selectedExtensionForConfig: Extension? = nil
    
    // Sắp xếp các extension theo tên
    private var extensions: [Extension] {
        repository.extensions.sorted(by: { $0.name < $1.name })
    }
    
    var body: some View {
        List {
            if !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
            
            Section(header: Text("Các tiện ích bóc tách truyện trong kho")) {
                if extensions.isEmpty {
                    Text("Kho này không có tiện ích nào.")
                        .foregroundColor(.gray)
                } else {
                    ForEach(extensions) { ext in
                        HStack(alignment: .top, spacing: 12) {
                            // Icon tiện ích (nếu có, hoặc hiển thị mặc định)
                            if let iconUrl = ext.iconUrl, let url = URL(string: iconUrl) {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                } placeholder: {
                                    Image(systemName: "puzzlepiece.extension")
                                        .foregroundColor(.accentColor)
                                }
                                .frame(width: 44, height: 44)
                                .cornerRadius(8)
                            } else {
                                Image(systemName: ext.type == "comic" ? "comicbook" : "book.closed")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.2))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(ext.name)
                                        .font(.headline)
                                    Text("v\(ext.version)")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                }
                                
                                Text(ext.sourceUrl)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                if let desc = ext.desc, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            
                            // Nút Trạng Thái / Cài Đặt
                            if loadingStates[ext.packageId] == true {
                                ProgressView()
                                    .frame(width: 60)
                            } else {
                                if ext.localPath.isEmpty {
                                    Button(action: {
                                        installExtension(ext)
                                    }) {
                                        Text("Cài đặt")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.accentColor)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                     HStack(spacing: 8) {
                                         Text("Đã cài")
                                             .font(.caption)
                                             .foregroundColor(.green)
                                             .fontWeight(.semibold)
                                         
                                         Button(action: {
                                             selectedExtensionForConfig = ext
                                         }) {
                                             Image(systemName: "gearshape")
                                                 .foregroundColor(.blue)
                                                 .padding(6)
                                                 .background(Color.blue.opacity(0.1))
                                                 .cornerRadius(6)
                                         }
                                         .buttonStyle(.plain)
                                         
                                         Button(action: {
                                             uninstallExtension(ext)
                                         }) {
                                             Image(systemName: "trash")
                                                 .foregroundColor(.red)
                                                 .padding(6)
                                                 .background(Color.red.opacity(0.1))
                                                 .cornerRadius(6)
                                         }
                                         .buttonStyle(.plain)
                                     }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedExtensionForConfig) { ext in
            ExtensionConfigView(ext: ext)
        }
    }
    
    private func installExtension(_ ext: Extension) {
        // Lấy registry item tương ứng từ thông tin trong db
        let item = ExtensionRegistryItem(
            name: ext.name,
            author: ext.author,
            path: repository.url.replacingOccurrences(of: "plugin.json", with: "extensions/\(ext.packageId)/plugin.zip"), // Fallback logic nếu path trống, thực tế path gốc được lưu
            version: ext.version,
            source: ext.sourceUrl,
            icon: ext.iconUrl,
            description: ext.desc,
            type: ext.type,
            locale: ext.locale
        )
        
        // Cố gắng sử dụng URL download chuẩn nếu VBook registry cung cấp
        var downloadUrl = item.path
        // Tìm xem link path gốc là gì từ plugin.json nếu ta lưu nó hoặc sinh trực tiếp
        // Trong syncExtensions ta có item.path, ở đây ta sẽ dùng logic hợp lý
        // Đọc lại từ URL Session hoặc nếu có lưu link zip trong Extension model
        // Để đơn giản, ta sẽ cho phép Extension model lưu trường downloadUrl.
        // Hãy cập nhật Extension.swift để lưu trường path tải zip!
        // Để không phải tạo lỗi biên dịch, ta sẽ giả định item.path đã được cấu hình trong Registry Item.
        
        // Vì trong model Extension.swift ta chưa lưu trường `zipUrl`, ta có thể sinh tự động:
        // ext.repository.url chính là URL của plugin.json, ví dụ: https://.../plugin.json
        // File zip nằm tại: https://.../extensions/packageId/plugin.zip hoặc lấy link tương ứng
        // Trong plugin.json thực tế của dat-bi, trường `path` chứa link tuyệt đối (https://raw.githubusercontent.com/dat-bi/ext-vbook/main/extensions/123ds/plugin.zip)
        // Nên để lấy link zip chuẩn, ta có thể xây dựng cấu trúc link zip tuyệt đối:
        if let repoUrl = URL(string: repository.url) {
            let baseRepoUrl = repoUrl.deletingLastPathComponent().absoluteString
            downloadUrl = "\(baseRepoUrl)extensions/\(ext.packageId)/plugin.zip"
        }
        
        let finalItem = ExtensionRegistryItem(
            name: ext.name,
            author: ext.author,
            path: downloadUrl,
            version: ext.version,
            source: ext.sourceUrl,
            icon: ext.iconUrl,
            description: ext.desc,
            type: ext.type,
            locale: ext.locale
        )
        
        loadingStates[ext.packageId] = true
        errorMessage = ""
        
        Task {
            do {
                let localFolder = try await ExtensionManager.shared.install(item: finalItem, packageId: ext.packageId)
                await MainActor.run {
                    ext.localPath = localFolder
                    try? modelContext.save()
                    loadingStates[ext.packageId] = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Lỗi cài đặt \(ext.name): \(error.localizedDescription)"
                    loadingStates[ext.packageId] = false
                }
            }
        }
    }
    
    private func uninstallExtension(_ ext: Extension) {
        guard !ext.localPath.isEmpty else { return }
        ExtensionManager.shared.uninstall(localPath: ext.localPath)
        ext.localPath = ""
        try? modelContext.save()
    }
}
