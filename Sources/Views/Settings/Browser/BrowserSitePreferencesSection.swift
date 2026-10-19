import SwiftUI

/// Section **Trang đã chỉnh riêng** của màn Cài đặt → Trình duyệt (plan §3.2): mỗi tên miền đã chỉnh trong menu
/// khiên của trình duyệt + chip mô tả chỉnh gì. Vuốt trái để xoá ⇒ tên miền về theo mặc định.
///
/// Đọc/ghi qua `BrowserSitePreferenceList.shared` (`@Observable`, ghi store rồi tự `reload()`). Xoá có hiệu lực từ
/// lượt nạp trang kế tiếp (không nạp lại tab đang mở).
///
/// Chip: `Tắt chặn QC` / `Máy tính` như mockup; thêm `Bật chặn QC` / `Điện thoại` cho bản ghi ngược chiều mặc định
/// (vd tắt chặn QC chung rồi bật lại cho một trang) — để không có dòng nào trống chip.
struct BrowserSitePreferencesSection: View {
    private var list: BrowserSitePreferenceList { BrowserSitePreferenceList.shared }

    var body: some View {
        let items = list.items
        Section {
            if items.isEmpty {
                Text("Chưa có trang nào. Chỉnh trong menu khiên của trình duyệt.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            } else {
                ForEach(items) { item in
                    row(item)
                }
                .onDelete { offsets in
                    let domains = offsets.compactMap { items.indices.contains($0) ? items[$0].domain : nil }
                    MainActor.assumeIsolated {
                        for domain in domains {
                            BrowserSitePreferenceList.shared.remove(domain: domain)
                            AppLogger.shared.log("🛡️ [BrowserSettings] Xoá chỉnh riêng của \(domain)")
                        }
                    }
                }
            }
        } header: {
            Text("Trang đã chỉnh riêng")
        } footer: {
            if !items.isEmpty {
                Text("Vuốt trái để xoá, trang về theo mặc định.")
            }
        }
    }

    private func row(_ item: BrowserSitePreference) -> some View {
        HStack(spacing: 8) {
            Text(item.domain)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            ForEach(Self.chips(for: item), id: \.self) { chip in
                Text(chip)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    private static func chips(for item: BrowserSitePreference) -> [String] {
        var chips: [String] = []
        if let adBlock = item.adBlock {
            chips.append(adBlock ? "Bật chặn QC" : "Tắt chặn QC")
        }
        if let desktop = item.desktop {
            chips.append(desktop ? "Máy tính" : "Điện thoại")
        }
        return chips
    }
}
