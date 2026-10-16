import SwiftUI

/// Sheet "Bộ lọc tiện ích" dạng **chip chọn nhiều** (`FlowLayout`).
///
/// Mỗi nhóm: chip "Tất cả" (sáng khi nhóm rỗng, bấm = bỏ chọn cả nhóm) rồi các giá trị; bỏ hết chip thì
/// "Tất cả" tự sáng lại. Luật lọc (HOẶC trong nhóm, VÀ giữa nhóm) nằm ở `RepositoryFilterPolicy`.
public struct FilterSheet: View {
    @Environment(\.dismiss) internal var dismiss
    public let allAuthors: [String]
    public let allLocales: [String]
    public let allTypes: [String]

    @Binding public var filterTypes: Set<String>
    @Binding public var filterLocales: Set<String>
    @Binding public var filterAuthors: Set<String>

    public init(
        allAuthors: [String],
        allLocales: [String],
        allTypes: [String],
        filterTypes: Binding<Set<String>>,
        filterLocales: Binding<Set<String>>,
        filterAuthors: Binding<Set<String>>
    ) {
        self.allAuthors = allAuthors
        self.allLocales = allLocales
        self.allTypes = allTypes
        self._filterTypes = filterTypes
        self._filterLocales = filterLocales
        self._filterAuthors = filterAuthors
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    chipGroup(title: "Loại tiện ích", options: allTypes, selection: $filterTypes) {
                        ExtensionDisplayCatalog.label(forType: $0)
                    }
                    chipGroup(title: "Ngôn ngữ", options: allLocales, selection: $filterLocales) {
                        ExtensionDisplayCatalog.label(forLocale: $0)
                    }
                    chipGroup(title: "Tác giả", options: allAuthors, selection: $filterAuthors) { $0 }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Bộ lọc tiện ích")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đặt lại") {
                        filterTypes = []
                        filterLocales = []
                        filterAuthors = []
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
        }
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
