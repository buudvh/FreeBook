import SwiftUI

/// Sheet chọn nguồn của Khám phá: tìm theo tên/link, lọc theo loại, ghim, mở Cấu hình tiện ích.
/// Tách khỏi `DiscoveryView.swift` để file đó còn chỗ dưới baseline dòng.
///
/// Trình duyệt của nguồn không còn mở từ dòng ở đây mà từ nút "Trình duyệt" của màn Cấu hình tiện ích; `onImport`
/// vẫn đi qua màn đó để "Import truyện" mở Chi tiết ở Khám phá như trước.
struct ExtensionSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    
    let activeExtensions: [Extension]
    @Binding var selectedExtensionId: String
    @Binding var extensionSearchQuery: String
    var onImport: ((_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void)? = nil
    
    @State private var configExtension: Extension? = nil
    @AppStorage("discoveryKindFilter") private var kindFilter = "" // chip loại: "" = tất cả, còn lại `ExtensionContentKind.rawValue`
    
    private var filteredExtensions: [Extension] {
        let kindScoped = activeExtensions.filter { SearchExtensionScopePolicy.matches($0, kindFilter: kindFilter) }
        let baseList: [Extension]
        if extensionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseList = kindScoped
        } else {
            baseList = kindScoped.filter {
                $0.name.localizedCaseInsensitiveContains(extensionSearchQuery) ||
                $0.sourceUrl.localizedCaseInsensitiveContains(extensionSearchQuery)
            }
        }
        
        // Đưa phần mở rộng đang chọn lên đầu danh sách, phần còn lại ghim → vừa dùng → A-Z
        return baseList.sorted { ext1, ext2 in
            let isSel1 = ext1.packageId == selectedExtensionId
            let isSel2 = ext2.packageId == selectedExtensionId
            if isSel1 != isSel2 {
                return isSel1
            }
            return ExtensionSortPolicy.areInIncreasingOrder(ext1, ext2)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Ô tìm kiếm tích hợp di chuyển lên trên cùng của danh sách để dễ sử dụng
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Tìm kiếm phần mở rộng", text: $extensionSearchQuery)
                        .textInputAutocapitalization(.none)
                        .submitLabel(.search)
                    
                    if !extensionSearchQuery.isEmpty {
                        Button(action: { extensionSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding()
                
                ExtensionKindFilterBar(selection: $kindFilter)
                Divider()
                
                // Danh sách phần mở rộng
                List(filteredExtensions) { ext in
                    let isSelected = ext.packageId == selectedExtensionId
                    HStack(spacing: 12) {
                        // Icon đại diện nguồn
                        ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 36)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ext.name)
                                .font(.body)
                                .fontWeight(isSelected ? .bold : .semibold)
                                .lineLimit(1) // Tránh tên tiện ích rớt dòng, tự động thu gọn bằng dấu ba chấm (...)
                            Text(ext.sourceUrl)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            BookKindBadge(kind: SearchExtensionScopePolicy.kind(of: ext), showsLabel: true, hidesText: false)
                        }
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                                .padding(.trailing, 4)
                        }
                        
                        // Nút cấu hình (Bánh răng)
                        Button(action: {
                            configExtension = ext
                        }) {
                            Image(systemName: "gearshape")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                        
                        // Nút Ghim (Pin)
                        Button(action: {
                            togglePin(ext)
                        }) {
                            Image(systemName: ext.isPinned ? "pin.fill" : "pin")
                                .font(.body)
                                .foregroundColor(ext.isPinned ? .white : .secondary)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedExtensionId = ext.packageId
                        // Chọn nguồn = duyệt chủ động ⇒ lên đầu nhóm "vừa dùng" (ghi file gom ~3 s).
                        ExtensionTransactionCoordinator.shared.markUsed(packageId: ext.packageId)
                        dismiss()
                    }
                    .listRowBackground(isSelected ? Color.white.opacity(0.1) : Color(.systemBackground))
                }
                .listStyle(.plain)
            }
            .navigationTitle("Phần mở rộng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(item: $configExtension) { ext in
                ExtensionConfigView(ext: ext, onImport: { detailUrl, packageId, sourceName in
                    importFromConfig(detailUrl: detailUrl, packageId: packageId, sourceName: sourceName)
                })
            }
        }
    }
    
    /// "Import truyện" trong trình duyệt mở từ màn Cấu hình: ba lớp đang chồng nhau (bảng chọn nguồn → Cấu hình →
    /// trình duyệt). Đóng sheet cấu hình + bảng chọn trước, rồi mới chuyển tiếp cho `DiscoveryView` sau ~0,35 s —
    /// đẩy màn Chi tiết vào stack của Khám phá khi các sheet còn đang trượt xuống thì lượt đẩy có thể bị bỏ.
    private func importFromConfig(detailUrl: String, packageId: String, sourceName: String) {
        configExtension = nil
        dismiss()
        let forward = onImport
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            forward?(detailUrl, packageId, sourceName)
        }
    }
    
    private func togglePin(_ ext: Extension) {
        let res = ExtensionTransactionCoordinator.shared.togglePinned(packageId: ext.packageId)
        if case .failure(let err) = res {
            AppLogger.shared.log("❌ [DiscoveryView] Lỗi ghim tiện ích: \(err.localizedDescription)")
        }
    }
}
