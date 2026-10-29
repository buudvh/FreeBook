import SwiftUI

/// Sheet "Bộ lọc tiện ích" dạng **chip chọn nhiều** (`FlowLayout`).
///
/// Mỗi nhóm: chip "Tất cả" (sáng khi nhóm rỗng, bấm = bỏ chọn cả nhóm) rồi các giá trị; bỏ hết chip thì
/// "Tất cả" tự sáng lại. Luật lọc (HOẶC trong nhóm, VÀ giữa nhóm) nằm ở `RepositoryFilterPolicy`.
///
/// `allTypes`/`allLocales` là **khoá nhóm** (`ExtensionFilterGroups`) theo thứ tự cố định, chỉ gồm nhóm có ít nhất
/// một tiện ích; chip hiện nhãn nhóm kèm số lượng, vd "Truyện chữ (494)". Danh mục và số đếm do caller tính **sau**
/// công tắc NSFW.
///
/// Công tắc "Nội dung nhạy cảm (NSFW)" mặc định **tắt** (`RepositoryFilterPolicy.includeNsfwDefaultsKey`): ẩn tiện
/// ích NSFW ở Kho và khi tìm mọi nguồn; Khám phá vẫn hiện tiện ích đã cài. "Đặt lại" đưa về tắt.
public struct FilterSheet: View {
    @Environment(\.dismiss) internal var dismiss
    public let allAuthors: [String]
    public let allLocales: [String]
    public let allTypes: [String]
    public let typeCounts: [String: Int]
    public let localeCounts: [String: Int]

    @Binding public var filterTypes: Set<String>
    @Binding public var filterLocales: Set<String>
    @Binding public var filterAuthors: Set<String>
    @Binding public var includeNsfw: Bool
    /// Số tiện ích NSFW đang bị ẩn (0 khi công tắc bật).
    public let hiddenNsfwCount: Int

    public init(
        allAuthors: [String],
        allLocales: [String],
        allTypes: [String],
        typeCounts: [String: Int] = [:],
        localeCounts: [String: Int] = [:],
        filterTypes: Binding<Set<String>>,
        filterLocales: Binding<Set<String>>,
        filterAuthors: Binding<Set<String>>,
        includeNsfw: Binding<Bool>,
        hiddenNsfwCount: Int = 0
    ) {
        self.allAuthors = allAuthors
        self.allLocales = allLocales
        self.allTypes = allTypes
        self.typeCounts = typeCounts
        self.localeCounts = localeCounts
        self._filterTypes = filterTypes
        self._filterLocales = filterLocales
        self._filterAuthors = filterAuthors
        self._includeNsfw = includeNsfw
        self.hiddenNsfwCount = hiddenNsfwCount
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    nsfwToggle
                    chipGroup(title: "Loại tiện ích", options: allTypes, selection: $filterTypes) {
                        Self.countedLabel(ExtensionFilterGroups.typeGroupLabel($0), count: typeCounts[$0])
                    }
                    chipGroup(title: "Ngôn ngữ", options: allLocales, selection: $filterLocales) {
                        let label = "\(ExtensionFilterGroups.localeGroupFlag($0)) \(ExtensionFilterGroups.localeGroupLabel($0))"
                        return Self.countedLabel(label, count: localeCounts[$0])
                    }
                    chipGroup(title: "Tác giả", options: allAuthors, selection: $filterAuthors) { $0 }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .pageTitle("Bộ lọc tiện ích")
            .presentationDragIndicator(.visible)
            .toolbar {
                // Không còn "Xong" (vuốt xuống để đóng); "Đặt lại" thành icon đỏ bên phải, giữ hành vi xoá lọc + đóng.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        filterTypes = []
                        filterLocales = []
                        filterAuthors = []
                        includeNsfw = false
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    .accessibilityLabel("Đặt lại bộ lọc")
                }
            }
        }
    }

    private var nsfwToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $includeNsfw) {
                Text("Nội dung nhạy cảm (NSFW)")
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
            Text(nsfwFootnote)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var nsfwFootnote: String {
        if includeNsfw {
            return "Đang hiện cả tiện ích NSFW ở Kho và khi tìm mọi nguồn."
        }
        let hidden = hiddenNsfwCount > 0 ? "Đang ẩn \(hiddenNsfwCount) tiện ích NSFW" : "Ẩn tiện ích NSFW"
        return hidden + " ở Kho và khi tìm mọi nguồn. Khám phá vẫn hiện tiện ích đã cài."
    }

    private func chipGroup(
        title: String,
        options: [String],
        selection: Binding<Set<String>>,
        label: @escaping (String) -> String
    ) -> some View {
        let selected = selection.wrappedValue
        // Giá trị đã chọn nhưng không còn trong danh mục (vd tác giả đã rời kho) vẫn hiện ở cuối để bỏ chọn
        // được — nếu không, nhóm đó lọc ra rỗng mà không có chip nào để tắt.
        let stale = selected.subtracting(options).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let summary = selected.isEmpty ? "tất cả" : "đã chọn \(selected.count)"

        return VStack(alignment: .leading, spacing: 10) {
            Text("\(title) · \(summary)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            FlowLayout(spacing: 8) {
                chip(title: "Tất cả", isSelected: selected.isEmpty) {
                    selection.wrappedValue = []
                }
                ForEach(options + stale, id: \.self) { value in
                    chip(title: label(value), isSelected: selected.contains(value)) {
                        var next = selection.wrappedValue
                        if next.contains(value) {
                            next.remove(value)
                        } else {
                            next.insert(value)
                        }
                        selection.wrappedValue = next
                    }
                }
            }
        }
    }

    /// "Nhãn (n)"; không có số (chip đã chọn nhưng nhóm không còn tiện ích) thì chỉ nhãn.
    private static func countedLabel(_ label: String, count: Int?) -> String {
        guard let count, count > 0 else { return label }
        return "\(label) (\(count))"
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
