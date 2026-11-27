import SwiftUI

/// Bảng duyệt danh sách tên riêng trích xuất từ văn bản truyện.
///
/// Từ 1.3.469 card **không** còn nút Lưu: nút Lưu là `Menu` 2 mục trên thanh điều hướng của
/// `ReaderAINameReviewSheet` (đúng khuôn `AddWordSheet`). Card chỉ còn hiển thị danh sách, sắp xếp,
/// chọn/bỏ chọn, sửa và xoá từng mục.
///
/// Hàng theo khuôn hàng VP/Name (`DictionaryEntryRow`, 1.3.1060): dòng 2 là **chữ** nghĩa (không còn ô nhập), không
/// còn nút bút chì — chạm khối chữ (tên + badge + nghĩa) ⇒ nơi dùng mở màn Sửa từ. Ô vuông chọn và ✕ là nút riêng
/// nên chạm chúng không mở màn sửa; card nằm trong `ScrollView` + `LazyVStack` (không phải `List`) nên `.plain` đủ.
public struct ReaderAINameReviewCardView: View {
    @Binding public var names: [AIExtractedName]
    public var onDelete: ((UUID) -> Void)? = nil
    /// Chạm thân hàng của một mục: nơi dùng mở màn Sửa từ (card không biết truyện nên không tự mở). `nil` ⇒ chạm
    /// không làm gì.
    public var onEdit: ((UUID) -> Void)? = nil
    /// ✕ › "Không phải name" (luồng "Lọc name local"): nơi dùng thêm mục vào danh sách loại bỏ; card bỏ mục khỏi danh
    /// sách sau khi gọi. `nil` (luồng AI) ⇒ ✕ là nút xoá như cũ; có ⇒ ✕ mở menu "Bỏ khỏi lần này" / "Không phải name".
    public var onBlock: ((UUID) -> Void)? = nil

    public enum SortMode {
        case selectedFirst
        case alphabetical
        /// "Nhiều lần nhất": số lần giảm dần, rồi chữ Hán tăng dần (đúng thứ tự bộ lọc name local trả). Chỉ có trong menu
        /// khi card mở với kiểu này (luồng lọc local) — luồng AI giữ menu cũ.
        case mostFrequent
    }

    @State private var sortMode: SortMode
    /// Kiểu sắp lúc mở card — quyết định menu có "Nhiều lần nhất" không.
    private let initialSortMode: SortMode

    public init(
        names: Binding<[AIExtractedName]>,
        onDelete: ((UUID) -> Void)? = nil,
        onEdit: ((UUID) -> Void)? = nil,
        initialSortMode: SortMode = .selectedFirst,
        onBlock: ((UUID) -> Void)? = nil
    ) {
        self._names = names
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.initialSortMode = initialSortMode
        self._sortMode = State(initialValue: initialSortMode)
        self.onBlock = onBlock
    }

    private var sortChipLabel: String {
        switch sortMode {
        case .selectedFirst: return "Đã chọn"
        case .alphabetical: return "A-Z"
        case .mostFrequent: return "Nhiều lần"
        }
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
                    if initialSortMode == .mostFrequent {
                        Button {
                            sortMode = .mostFrequent
                            applySorting()
                        } label: {
                            HStack {
                                Text("Nhiều lần nhất")
                                if sortMode == .mostFrequent {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

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
                        Text(sortChipLabel)
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

            // Danh sách tên riêng. `LazyVStack`: mỗi lần chọn/bỏ chọn (hay sửa nghĩa) `names` đổi, `VStack` thường
            // cập nhật lại MỌI hàng — vài trăm tên là giật; lazy chỉ dựng hàng đang hiện.
            LazyVStack(spacing: 6) {
                ForEach($names) { $item in
                    HStack(spacing: 4) {
                        // Vùng chạm 44×44 (mức tối thiểu của Apple) thay cho icon 16 pt trơn.
                        Button(action: {
                            item.isSelected.toggle()
                        }) {
                            Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(item.isSelected ? Color(red: 90/255.0, green: 170/255.0, blue: 255/255.0) : .secondary)
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                // Cỡ chữ theo hàng VP/Name (`DictionaryEntryRow`): tên `.headline`, nghĩa `.subheadline`.
                                Text(item.original)
                                    .font(.headline)
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

                            Text(item.suggestedMeaning)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        // Thân hàng (chữ + khoảng trống tới ✕) mở màn Sửa từ — như `DictionaryEntryRow`, không bọc cả
                        // hàng trong `Button`. Chọn/bỏ chọn chỉ còn ở ô vuông bên trái.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onEdit?(item.id)
                        }

                        // Nút xóa từng mục; luồng lọc local (`onBlock`) ⇒ menu hai lựa chọn.
                        removeControl(id: item.id, term: item.original)
                    }
                    // Không đệm hai bên: khung 44 pt của ô chọn (trái) và ✕ (phải) đã tự chừa lề, hai icon cách mép đều nhau.
                    .padding(.vertical, 4)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                    .accessibilityAction(named: "Sửa") { onEdit?(item.id) }
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

    /// Nút xoá (thùng rác) của một hàng. Luồng AI (`onBlock == nil`): xoá ngay như cũ. Luồng lọc local: menu "Bỏ khỏi lần này" (chỉ bỏ khỏi
    /// danh sách đang duyệt) / "Không phải name" (bỏ + thêm vào danh sách loại bỏ qua `onBlock`).
    @ViewBuilder
    private func removeControl(id: UUID, term: String) -> some View {
        if onBlock != nil {
            Menu {
                Button {
                    deleteItem(id: id)
                } label: {
                    Label("Bỏ khỏi lần này", systemImage: "minus.circle")
                }
                Button(role: .destructive) {
                    blockItem(id: id)
                } label: {
                    Label("Không phải name", systemImage: "nosign")
                }
            } label: {
                removeIcon
            }
            .accessibilityLabel("Bỏ \(term)")
        } else {
            Button(action: {
                deleteItem(id: id)
            }) {
                removeIcon
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bỏ \(term)")
        }
    }

    /// Nút xoá **giống hàng danh sách từ điển** (`DictionaryEntryRow`: `trash` đỏ `.subheadline` — anh Bửu: "đổi thành
    /// nút xóa giống danh sách trong từ điển"), vùng chạm 44 × 44 bằng ô vuông chọn bên trái (anh chê ✕ cũ nhỏ khó bấm).
    private var removeIcon: some View {
        Image(systemName: "trash")
            .font(.subheadline)
            .foregroundColor(.red)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
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

    /// Báo nơi dùng **trước** khi xoá: nơi dùng cần tra mục theo `id` (vd lấy khoá để xoá hẳn khỏi tin nguồn).
    private func deleteItem(id: UUID) {
        onDelete?(id)
        names.removeAll(where: { $0.id == id })
    }

    /// "Không phải name": báo nơi dùng **trước** (còn tra được mục theo `id`) rồi bỏ khỏi danh sách.
    private func blockItem(id: UUID) {
        onBlock?(id)
        names.removeAll(where: { $0.id == id })
    }

    private func applySorting() {
        switch sortMode {
        case .mostFrequent:
            names.sort { (a, b) -> Bool in
                if a.occurrenceCount != b.occurrenceCount {
                    return a.occurrenceCount > b.occurrenceCount
                }
                return a.original < b.original
            }
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
