import SwiftUI

/// Các section cấu hình thứ tự ưu tiên rule, dùng chung cho màn **chung** và màn **riêng của truyện**.
///
/// Ba section riêng thay vì một danh sách 6 hàng có `moveDisabled`: để chung một section thì `onMove`
/// vẫn cho kéo một hàng lên trước hàng bị khoá và phải tự kẹp chỉ số. Tách section là SwiftUI không
/// bao giờ sinh ra thao tác đó.
struct QuickTranslationRulePriorityListView: View {
    typealias Priority = QuickTranslationRulePriorityConfiguration

    @Binding var configuration: Priority.Configuration

    var body: some View {
        Group {
            presetSection

            Section {
                lockedRow(
                    title: "Vị trí xuất hiện",
                    systemImage: "text.alignleft",
                    detail: "Rule khớp gần đầu dòng hơn được xét trước. Không đổi được vì cách chọn rule dựa trên thứ tự này."
                )
            } header: {
                Text("Luôn xét đầu tiên")
            }

            Section {
                ForEach(configuration.order, id: \.self, content: movableRow)
                    .onMove(perform: move)
            } header: {
                Text("Xét theo thứ tự này")
            } footer: {
                Text("Bấm Sửa ở góc trên rồi kéo để đổi thứ tự. Bấm vào một hàng để đổi chiều so sánh. Khi hai rule chồng nhau, app so từng tiêu chí từ trên xuống và DỪNG ở tiêu chí đầu tiên phân định được — các tiêu chí bên dưới không được xét nữa.")
            }

            Section {
                lockedRow(
                    title: "Số dòng trong file",
                    systemImage: "number",
                    detail: "Rule ở dòng sớm hơn thắng. Luôn ở cuối để kết quả không đổi giữa hai lần chạy."
                )
            } header: {
                Text("Luôn xét cuối cùng")
            }
        }
    }

    // MARK: - Bộ dựng sẵn

    @ViewBuilder
    private var presetSection: some View {
        Section {
            ForEach(Priority.Preset.allCases, id: \.self) { preset in
                let isSelected = configuration.matchingPreset == preset
                Button {
                    configuration = preset.configuration
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.title)
                                .font(.subheadline.weight(.medium))
                            Text(preset.explanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Bộ dựng sẵn")
        } footer: {
            Text("Kéo tay ở phần dưới sẽ tạo thứ tự riêng, lúc đó không bộ nào được đánh dấu.")
        }
    }

    // MARK: - Hàng

    private func movableRow(_ key: Priority.Key) -> some View {
        Button {
            configuration = configuration.togglingDirection(of: key)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: key.systemImage)
                        .foregroundColor(.accentColor)
                    Text(key.title)
                        .font(.subheadline.weight(.medium))
                }
                Text(key.directionLabel(descending: configuration.isDescending(key)))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                Text(key.explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func lockedRow(title: String, systemImage: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Image(systemName: "lock.fill")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var keys = configuration.order
        keys.move(fromOffsets: source, toOffset: destination)
        configuration = configuration.reordering(to: keys)
    }
}
