import SwiftUI

/// Nội dung ngăn kéo **chọn nguồn** của Khám phá (trượt từ mép trái — `discoverySourcePicker`): ô tìm viên thuốc kiểu
/// mục lục (tìm theo tên/link) + nút chọn loại dạng menu (`ExtensionKindMenuButton`) **đứng yên ở đầu**, rồi danh sách
/// nguồn tự cuộn bên dưới (ngăn kéo mở với `contentScrolls: false`, 1.3.707) — bấm hàng để
/// chọn, ⚙ mở Cấu hình tiện ích (ⓘ Chi tiết nguồn với nguồn Legado), 📌 ghim. Viên NSFW nằm ở dòng tiêu đề ngăn kéo
/// (`ExtensionNsfwToggle`). Không còn hàng chip loại: kéo cuộn ngang hàng chip tranh với vuốt đóng ngăn kéo.
///
/// Ngăn kéo nằm ở cửa sổ nổi riêng (`SideDrawerMenuWindowManager`) nên:
/// - Từ khoá tìm là `@State` của chính view này (không phải Binding của màn): Binding sang cây view khác không làm
///   ngăn kéo vẽ lại khi gõ.
/// - Chọn nguồn / mở Cấu hình / Chi tiết nguồn đi qua `sideDrawerMenuDismiss`: ngăn kéo bắt đầu trượt ra rồi màn
///   Khám phá mới đổi nguồn hay trình bày sheet (`DiscoverySourcePickerModifier`).
/// - Ghim / chọn loại đổi giá trị ⇒ `refreshContent()` để ngăn kéo vẽ lại ngay.
///
/// Trình duyệt của nguồn không mở từ dòng ở đây mà từ dòng "Mở trình duyệt" trong menu header Khám phá
/// (`DiscoverySourceMenuButton`) hoặc nút "Trình duyệt" của màn Cấu hình tiện ích.
struct ExtensionSelectorView: View {
    let activeExtensions: [Extension]
    let selectedExtensionId: String
    let onSelect: (Extension) -> Void
    let onOpenConfig: (Extension) -> Void
    let onOpenLegadoDetail: (Extension) -> Void

    @Environment(\.sideDrawerMenuDismiss) private var dismissDrawer
    @State private var searchQuery = ""
    @AppStorage("discoveryKindFilter") private var kindFilter = "" // loại: "" = tất cả, còn lại `ExtensionContentKind.rawValue`

    private var filteredExtensions: [Extension] {
        let kindScoped = activeExtensions.filter { SearchExtensionScopePolicy.matches($0, kindFilter: kindFilter) }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseList = query.isEmpty ? kindScoped : kindScoped.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.sourceUrl.localizedCaseInsensitiveContains(query)
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
        let list = filteredExtensions
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                ChapterTOCSearchField(
                    text: $searchQuery,
                    placeholder: "Tìm kiếm \(activeExtensions.count) nguồn",
                    palette: .system
                )
                ExtensionKindMenuButton(selection: $kindFilter) { dismissDrawer.refreshContent() }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.bottom, 4)

            // Ngăn kéo gắn `contentScrolls: false` ⇒ chỉ danh sách cuộn, hàng tìm ở trên luôn đứng yên.
            ScrollView {
                if list.isEmpty {
                    Text("Không có nguồn nào khớp")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(list, id: \.packageId) { ext in
                            row(ext)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row(_ ext: Extension) -> some View {
        let isSelected = ext.packageId == selectedExtensionId
        return HStack(spacing: 10) {
            ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 34)

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

            Spacer(minLength: 4)

            // Nút cấu hình (Bánh răng). Nguồn Legado không có màn cấu hình/sửa script của tiện ích JS — mở màn đó còn
            // cho đổi `type` trong metadata, biến nguồn thành "tiện ích JS" ⇒ nguồn Legado mở màn Chi tiết nguồn.
            let isLegado = LegadoSourcePolicy.isLegado(ext)
            Button(action: {
                dismissDrawer(then: {
                    if isLegado {
                        onOpenLegadoDetail(ext)
                    } else {
                        onOpenConfig(ext)
                    }
                })
            }) {
                Image(systemName: isLegado ? "info.circle" : "gearshape")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLegado ? "Chi tiết nguồn \(ext.name)" : "Cấu hình \(ext.name)")

            Button(action: { togglePin(ext) }) {
                Image(systemName: ext.isPinned ? "pin.fill" : "pin")
                    .font(.body)
                    .foregroundColor(ext.isPinned ? .white : .secondary)
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ext.isPinned ? "Bỏ ghim \(ext.name)" : "Ghim \(ext.name)")
        }
        .padding(.leading, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            dismissDrawer(then: { onSelect(ext) })
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func togglePin(_ ext: Extension) {
        let res = ExtensionTransactionCoordinator.shared.togglePinned(packageId: ext.packageId)
        if case .failure(let err) = res {
            AppLogger.shared.log("❌ [DiscoveryView] Lỗi ghim tiện ích: \(err.localizedDescription)")
        }
        dismissDrawer.refreshContent()
    }
}
