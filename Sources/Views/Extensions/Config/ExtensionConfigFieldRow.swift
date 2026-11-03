import SwiftUI

/// Một dòng cài đặt của khối `config` — dùng chung cho màn Cấu hình tiện ích và sheet Bộ lọc (`ExtensionFilterSheet`).
/// Đọc/ghi thẳng vào `values` (giá trị dạng chữ theo khoá); việc lưu do màn chứa nó lo.
///
/// Năm dáng dòng:
/// - chọn (`select`, mọi `format` — `single`, bỏ trống, `text`… đều là chọn **một**; hợp đồng bỏ `multiple`): nút
///   menu rộng hết dòng ở dưới tiêu đề — lựa chọn dài ("Tối đa 20 phản hồi mỗi bình luận") để bên phải sẽ bị cắt;
/// - danh sách (`list`): số dòng bên phải, chạm mở `ExtensionConfigListEditor` (màn chứa phải có `NavigationStack`);
/// - công tắc: tiêu đề + khoá bên trái, `Toggle` bên phải;
/// - số: ô gọn bên phải (giá trị ngắn);
/// - chữ (thường là URL dài): tiêu đề + khoá, bộ nút ↺ · xoá · sao chép · dán bên phải, ô nhập **rộng hết dòng**
///   ở dưới — để bên phải thì URL bị cắt chỉ còn vài ký tự. Giá trị mặc định là chữ mờ trong ô khi ô trống.
struct ExtensionConfigFieldRow: View {
    let key: String
    let item: ExtensionConfigSchema.Item
    @Binding var values: [String: String]
    /// Nút nhỏ ở đầu phải dòng tiêu đề — chỉ dòng chọn (`select`) có chỗ trống ở đó (sheet Bộ lọc đặt ↺ Đặt lại).
    var labelAccessory: AnyView? = nil

    var body: some View {
        if item.mode == "select" {
            selectRow
        } else if item.mode == "list" {
            NavigationLink {
                ExtensionConfigListEditor(title: item.title ?? key, subtitle: item.subtitle, value: textBinding)
            } label: {
                HStack(spacing: 12) {
                    label
                    Spacer(minLength: 8)
                    Text("\(ExtensionConfigListEditor.items(from: values[key] ?? "").count) dòng")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        } else if item.isToggle {
            Toggle(isOn: Binding(
                get: { (values[key] ?? item.default ?? "false") == "true" },
                set: { values[key] = $0 ? "true" : "false" }
            )) {
                label
            }
        } else if item.format == "number" {
            HStack(spacing: 12) {
                label
                Spacer(minLength: 8)
                TextField(item.default ?? "", text: textBinding)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.callout.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(width: 90)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    label
                    Spacer(minLength: 8)
                    TextFieldClipboardButtons(text: textBinding, defaultValue: item.default)
                }
                TextField(item.default ?? "", text: textBinding)
                    .font(.footnote)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.vertical, 2)
        }
    }

    /// Menu kiểu ô chọn của form đăng nhập Legado (`LegadoLoginFieldView.selectField`): dấu ✓ ở lựa chọn đang hiện.
    private var selectRow: some View {
        let selected = ExtensionConfigSchema.displayedSelection(values[key], item: item)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                label
                if let labelAccessory {
                    Spacer(minLength: 8)
                    labelAccessory
                }
            }
            Menu {
                ForEach(Array(item.values.enumerated()), id: \.offset) { _, option in
                    Button(action: { values[key] = option }) {
                        if option == selected {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selected)
                        .font(.footnote)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .disabled(item.values.isEmpty)
        }
        .padding(.vertical, 2)
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    /// Tiêu đề + dòng phụ là **khoá** (chữ đều, một dòng) + `subtitle` của tiện ích nếu có (hiện ở mọi kiểu — hợp đồng
    /// chỉ nói `toggle`/`list` nhưng tiện ích thật viết cả cho `select`/`input`). Không ghi "mặc định X" ở đây: mặc định
    /// thường là URL dài, kéo dòng phụ xuống 3–4 dòng; nó đã là chữ mờ trong ô và là đích của nút ↺.
    private var label: some View {
        let title = item.title ?? key
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
            if title != key {
                Text(key)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
