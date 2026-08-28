import SwiftUI

/// Nội dung nút `?` của màn Check rule. Tách file riêng vì `ReaderRuleTraceOverlayView` đã sát trần
/// 400 dòng của `check_architecture.py`.
struct ReaderRuleTraceGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Dải chip nói gì") {
                    legendRow(.winner, title: "Xanh đậm + dấu ✓", detail: "Rule đang thắng: chính nó đổi chữ ở cụm này.")
                    legendRow(.conflicting, title: "Xanh nhạt", detail: "Rule cũng khớp nhưng chồng lấn và thua theo thứ tự ưu tiên.")
                    legendRow(.disabled, title: "Xanh xám", detail: "Rule đang bị tắt, bị tắt token, hoặc quá phức tạp nên không chạy.")
                }

                Section("Badge R / C") {
                    Text("**R** = rule của bộ **riêng** truyện này. **C** = rule của bộ **chung**.")
                    Text("Rule riêng **thắng** rule chung khi hai bên trùng mọi tiêu chí ưu tiên khác.")
                }

                Section("Thao tác") {
                    Text("**Bấm một ký tự** ở thanh trên: chọn cả **cụm** mà rule phủ ký tự đó, không phải một ký tự lẻ.")
                    Text("**Bấm một chip**: xem nghĩa rule đó sinh ra và nghĩa từng token của nó.")
                    Text("**Bấm chip token** ở dải giữa: tô đúng phần chữ gốc mà token đã nuốt.")
                    Text("**Ấn giữ một chip**: sửa / bật / tắt / xoá rule đó.")
                    Text("**Nút +**: thêm rule mới, mẫu điền sẵn bằng cụm đang chọn; chọn được lưu vào bộ riêng hay bộ chung.")
                }

                Section("Tắt rule hoạt động thế nào") {
                    Text("Tắt ở **bộ chung** là tắt cho **mọi** truyện. Muốn dùng lại rule đó ở đúng một truyện thì thêm mẫu vào **bộ rule riêng** của truyện.")
                    Text("Tắt ở **truyện này** chỉ ảnh hưởng truyện đang đọc.")
                    Text("Rule của bộ riêng **không** bị lệnh tắt chung chi phối.")
                }

                Section("Thứ tự ưu tiên khi nhiều rule cùng khớp") {
                    Text("1. Vị trí bắt đầu bên trái\n2. Literal dài hơn\n3. Khoảng wildcard hẹp hơn\n4. Match dài hơn\n5. Rule **riêng** trước rule **chung**\n6. Dòng nguồn nhỏ hơn")
                        .font(.footnote)
                }

                Section {
                    Text("Đổi rule xong, khi đóng màn này đoạn văn sẽ được dịch lại.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Cách dùng Check rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    private func legendRow(_ style: ReaderRuleChipStyle, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(style.borderColor, lineWidth: style.borderWidth)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.12, green: 0.12, blue: 0.15)))
                .frame(width: 34, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(style.textColor)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
