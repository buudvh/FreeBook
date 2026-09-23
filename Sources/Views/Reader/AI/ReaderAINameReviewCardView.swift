import SwiftUI

/// Bảng duyệt danh sách tên riêng trích xuất từ văn bản truyện.
public struct ReaderAINameReviewCardView: View {
    @Binding public var names: [AIExtractedName]
    public let onSaveSelected: ([AIExtractedName]) -> Void

    public init(
        names: Binding<[AIExtractedName]>,
        onSaveSelected: @escaping ([AIExtractedName]) -> Void
    ) {
        self._names = names
        self.onSaveSelected = onSaveSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.blue)
                    Text("Tên riêng tìm thấy (\(names.count))")
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                Button(allSelected ? "Bỏ chọn tất cả" : "Chọn tất cả") {
                    toggleSelectAll()
                }
                .font(.system(size: 11))
            }
            .padding(.bottom, 2)

            // Danh sách tên riêng
            VStack(spacing: 6) {
                ForEach($names) { $item in
                    HStack(spacing: 8) {
                        Button(action: { item.isSelected.toggle() }) {
                            Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(item.isSelected ? .blue : .secondary)
                                .font(.system(size: 15))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.original)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.primary)

                                Text(item.category)
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)

                                if item.occurrenceCount > 1 {
                                    Text("\(item.occurrenceCount) lần")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }

                            TextField("Nghĩa Hán-Việt/Dịch", text: $item.suggestedMeaning)
                                .font(.system(size: 12))
                                .textFieldStyle(.plain)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
            }

            // Nút Lưu
            Button(action: {
                onSaveSelected(names.filter { $0.isSelected })
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Lưu \(selectedCount) mục đã chọn vào từ điển truyện")
                        .fontWeight(.bold)
                    Spacer()
                }
                .font(.system(size: 13))
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(selectedCount == 0)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }

    private var allSelected: Bool {
        names.allSatisfy { $0.isSelected }
    }

    private var selectedCount: Int {
        names.filter { $0.isSelected }.count
    }

    private func toggleSelectAll() {
        let target = !allSelected
        for idx in names.indices {
            names[idx].isSelected = target
        }
    }
}
