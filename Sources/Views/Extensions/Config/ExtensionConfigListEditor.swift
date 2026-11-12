import SwiftUI

/// Màn sửa một mục config `mode: "list"` (trang đẩy vào từ `ExtensionConfigView`): người dùng thêm/sửa/xoá từng dòng
/// chữ tự do — vd nhiều `api_key` để tiện ích xoay vòng.
///
/// Giá trị là **chuỗi** JSON của mảng chuỗi (`"[\"a\",\"b\"]"`, hợp đồng) ghi thẳng vào `value` — binding của
/// `ExtensionConfigView.userValues`, nên lượt lưu (chờ 0,4 s, flush khi đóng màn) đi đúng đường của ô chữ.
/// Dòng trống giữ trên màn để gõ tiếp nhưng không vào giá trị. Giá trị cũ không phải mảng JSON (bản cũ của màn
/// Cấu hình chỉ có ô chữ thô) ⇒ coi là một dòng.
struct ExtensionConfigListEditor: View {
    let title: String
    let subtitle: String?
    @Binding var value: String

    private struct Row: Identifiable {
        let id = UUID()
        var text: String
    }

    @State private var rows: [Row] = []
    @State private var didLoad = false
    @FocusState private var focusedRow: UUID?

    var body: some View {
        List { Group {
            if let subtitle, !subtitle.isEmpty {
                Section {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            Section {
                if rows.isEmpty {
                    Text("Chưa có dòng nào. Bấm + để thêm.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        TextField("Nhập giá trị", text: binding(for: row.id))
                            .font(.subheadline)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedRow, equals: row.id)
                        Button(role: .destructive, action: { remove(row.id) }) {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Xoá dòng")
                    }
                }
                .onDelete { offsets in
                    rows.remove(atOffsets: offsets)
                    commit()
                }
            }
        }.glassSheetRows() }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .backPageTitle(title)
        .floatingAddButton("Thêm dòng") {
            let row = Row(text: "")
            rows.append(row)
            // Ô mới chỉ có sau lượt vẽ kế tiếp — đặt focus ngay thì `TextField` chưa tồn tại.
            Task { @MainActor in focusedRow = row.id }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            rows = Self.items(from: value).map { Row(text: $0) }
        }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { rows.first(where: { $0.id == id })?.text ?? "" },
            set: { newValue in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index].text = newValue
                commit()
            }
        )
    }

    private func remove(_ id: UUID) {
        rows.removeAll { $0.id == id }
        commit()
    }

    private func commit() {
        let next = Self.encode(rows.map(\.text))
        if next != value { value = next }
    }

    // MARK: - Mã hoá giá trị

    /// Các dòng của giá trị đã lưu (cũng dùng để đếm số dòng ở màn Cấu hình).
    static func items(from value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return array.map(ExtensionConfigValueFormatter.text).filter { !Self.isBlank($0) }
        }
        return [value]
    }

    /// Chuỗi JSON của các dòng không trống; không còn dòng nào ⇒ `"[]"`.
    static func encode(_ items: [String]) -> String {
        let kept = items.filter { !isBlank($0) }
        guard let data = try? JSONSerialization.data(withJSONObject: kept, options: [.withoutEscapingSlashes]),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
