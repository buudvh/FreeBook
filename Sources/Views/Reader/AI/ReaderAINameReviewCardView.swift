import SwiftUI

/// Bảng duyệt danh sách tên riêng trích xuất từ văn bản truyện.
///
/// Từ 1.3.469 card **không** còn nút Lưu: nút Lưu là `Menu` 2 mục trên thanh điều hướng của
/// `ReaderAINameReviewSheet` (đúng khuôn `AddWordSheet`). Card chỉ còn hiển thị danh sách, sắp xếp,
/// chọn/bỏ chọn và xoá từng mục.
public struct ReaderAINameReviewCardView: View {
    @Binding public var names: [AIExtractedName]
    public var onDelete: ((UUID) -> Void)? = nil

    public enum SortMode {
        case selectedFirst
        case alphabetical
    }

    @State private var sortMode: SortMode = .selectedFirst

    public init(
        names: Binding<[AIExtractedName]>,
        onDelete: ((UUID) -> Void)? = nil
    ) {
        self._names = names
        self.onDelete = onDelete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(Color(red: 90/255.0, green: 170/255.0, blue: 255/255.0))
                    Text("Tên riêng (\(names.count))")
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()

                // Menu & Nút Sắp xếp
                Menu {
                    Button {
                        sortMode = .selectedFirst
                        applySorting()
                    } label: {
                        HStack {
                            Text("Đã chọn trước")
                            if sortMode == .selectedFirst {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        sortMode = .alphabetical
                        applySorting()
                    } label: {
                        HStack {
                            Text("Từ A → Z (Hán Việt)")
                            if sortMode == .alphabetical {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    Button {
                        applySorting()
                    } label: {
                        Label("Sắp xếp lại ngay", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortMode == .selectedFirst ? "Đã chọn" : "A-Z")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 90/255.0, green: 170/255.0, blue: 255/255.0))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }

                Button(allSelected ? "Bỏ chọn" : "Chọn hết") {
                    toggleSelectAll()
                }
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.bottom, 2)

            // Danh sách tên riêng
            VStack(spacing: 6) {
                ForEach($names) { $item in
                    HStack(spacing: 8) {
                        Button(action: {
                            item.isSelected.toggle()
                        }) {
                            Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(item.isSelected ? Color(red: 90/255.0, green: 170/255.0, blue: 255/255.0) : .secondary)
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.original)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)

                                Text(item.category)
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(white: 0.25))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                    .fixedSize(horizontal: true, vertical: false)

                                if item.hasInBookNames {
                                    Text("NE")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.red.opacity(0.25))
                                        .foregroundColor(.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.red.opacity(0.8), lineWidth: 0.8)
                                        )
                                        .cornerRadius(4)
                                        .fixedSize(horizontal: true, vertical: false)
                                }

                                if item.hasInBookVP {
                                    Text("VP")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color(red: 0.3, green: 0.6, blue: 0.9).opacity(0.25))
                                        .foregroundColor(.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color(red: 0.45, green: 0.75, blue: 1.0).opacity(0.8), lineWidth: 0.8)
                                        )
                                        .cornerRadius(4)
                                        .fixedSize(horizontal: true, vertical: false)
                                }

                                if item.occurrenceCount > 1 {
                                    Text("\(item.occurrenceCount) lần")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }

                            TextField("Nghĩa Hán-Việt/Dịch", text: $item.suggestedMeaning)
                                .font(.system(size: 12))
                                .textFieldStyle(.plain)
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 4)

                        // Nút xóa từng mục
                        Button(action: {
                            deleteItem(id: item.id)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            applySorting()
        }
    }

    private var allSelected: Bool {
        names.allSatisfy { $0.isSelected }
    }

    private func toggleSelectAll() {
        let target = !allSelected
        for idx in names.indices {
            names[idx].isSelected = target
        }
    }

    private func deleteItem(id: UUID) {
        names.removeAll(where: { $0.id == id })
        onDelete?(id)
    }

    private func applySorting() {
        switch sortMode {
        case .selectedFirst:
            names.sort { (a, b) -> Bool in
                if a.isSelected != b.isSelected {
                    return a.isSelected && !b.isSelected
                }
                let aStr = a.suggestedMeaning.isEmpty ? a.original : a.suggestedMeaning
                let bStr = b.suggestedMeaning.isEmpty ? b.original : b.suggestedMeaning
                return aStr.localizedStandardCompare(bStr) == .orderedAscending
            }
        case .alphabetical:
            names.sort { (a, b) -> Bool in
                let aStr = a.suggestedMeaning.isEmpty ? a.original : a.suggestedMeaning
                let bStr = b.suggestedMeaning.isEmpty ? b.original : b.suggestedMeaning
                return aStr.localizedStandardCompare(bStr) == .orderedAscending
            }
        }
    }
}
