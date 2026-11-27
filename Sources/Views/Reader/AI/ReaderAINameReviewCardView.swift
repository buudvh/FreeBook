import SwiftUI

/// Bảng duyệt danh sách tên riêng trích xuất từ văn bản truyện.
///
/// Từ 1.3.469 card **không** còn nút Lưu: nút Lưu là `Menu` 2 mục trên thanh điều hướng của
/// `ReaderAINameReviewSheet` (đúng khuôn `AddWordSheet`). Card chỉ còn hiển thị danh sách, ô tìm, sắp xếp,
/// chọn/bỏ chọn, sửa và xoá từng mục. Sắp xếp ở `+Sorting`, ô tìm + phần đang hiện + "Chọn hết" ở `+Filtering`.
///
/// Hàng theo khuôn hàng VP/Name (`DictionaryEntryRow`, 1.3.1060): dòng 2 là **chữ** nghĩa (không còn ô nhập), không
/// còn nút bút chì — chạm khối chữ (tên + badge + nghĩa) ⇒ nơi dùng mở màn Sửa từ. Ô vuông chọn và ✕ là nút riêng
/// nên chạm chúng không mở màn sửa; card nằm trong `ScrollView` + `LazyVStack` (không phải `List`) nên `.plain` đủ.
///
/// Khối đầu **dính** (plan `2026-11-27-phan-loai-name` mục L14, anh Bửu: "các chip và search hiển thị kiểu sticky để
/// scroll xuống vẫn thấy"): cả thẻ là **một** `LazyVStack(pinnedViews: [.sectionHeaders])` với một `Section` — đầu thẻ
/// (số name, sắp xếp, Chọn hết / Bỏ chọn) + ô tìm + hàng chip loại (chỉ luồng lọc local) là tiêu đề section, cuộn xuống vẫn
/// nằm trên cùng vùng cuộn của sheet. Thẻ phải là con trực tiếp của `ScrollView` (`ReaderAINameReviewSheet`) — bọc thêm
/// `VStack` / `List` là mất ghim. Tiêu đề tô nền đặc bằng nền thẻ (`cardBackground`, gồm cả dải đệm 12 pt phía trên) để
/// hàng cuộn qua bên dưới không lộ chữ. Không đổ bóng lúc dính (đo vị trí cần `onGeometryChange` — iOS 18).
public struct ReaderAINameReviewCardView: View {
    @Binding public var names: [AIExtractedName]
    public var onDelete: ((UUID) -> Void)? = nil
    /// Chạm thân hàng của một mục: nơi dùng mở màn Sửa từ (card không biết truyện nên không tự mở). `nil` ⇒ chạm
    /// không làm gì.
    public var onEdit: ((UUID) -> Void)? = nil
    /// Thùng rác › "Không phải name" (luồng "Lọc name local"): nơi dùng thêm mục vào danh sách loại bỏ; card bỏ mục khỏi
    /// danh sách sau khi gọi. Có ⇒ thùng rác mở menu "Bỏ khỏi lần này" / "Không phải name". Luồng AI dùng `onToggleStrike`
    /// (gạch / bỏ gạch); không truyền cả hai ⇒ thùng rác xoá khỏi danh sách đang duyệt.
    public var onBlock: ((UUID) -> Void)? = nil
    /// Luồng AI (anh Bửu 2026-11-27): có ⇒ thùng rác **gạch** hàng thay cho xoá; hàng gạch hiện ↶ Hoàn tác (bấm = bỏ gạch).
    /// Trạng thái gạch do nơi dùng giữ (`struckKeys`, khoá = vế trái đã trim) và lưu vào tin nguồn.
    public var onToggleStrike: ((UUID) -> Void)? = nil
    /// Khoá đang gạch — hàng gạch ngang + mờ, ô chọn khoá, không mở màn sửa, "Chọn hết" bỏ qua.
    public var struckKeys: Set<String> = []
    /// Luồng "Lọc name local" (mockup LAC khung 3): hàng chip lọc theo loại (`ReaderAINameReviewCategoryBar`) + badge loại
    /// có màu. Chip (cùng ô tìm) **chỉ ẩn hàng**: "Chọn hết" / "Bỏ chọn" áp lên mục đang hiện, còn số ở tiêu đề và nút Lưu
    /// của sheet vẫn tính trên cả `names`, kể cả mục đang bị ẩn (`+Filtering`). Luồng AI: `false` (không chip, badge xám).
    public var showsCategoryFilter: Bool = false

    // `internal` (không `private`): `+Sorting` / `+Filtering` dùng chung.
    @State var sortMode: SortMode
    /// Nhóm chip đang chọn (`nil` = Tất cả); chỉ dùng khi `showsCategoryFilter`.
    @State var categoryFilter: LocalNameFilter.Category?
    /// Chữ trong ô tìm (`+Filtering`) — cả hai luồng.
    @State var searchText: String = ""
    /// Kiểu sắp lúc mở card — quyết định menu có các kiểu theo số lần không.
    let initialSortMode: SortMode

    public init(
        names: Binding<[AIExtractedName]>,
        onDelete: ((UUID) -> Void)? = nil,
        onEdit: ((UUID) -> Void)? = nil,
        initialSortMode: SortMode = .selectedFirst,
        onBlock: ((UUID) -> Void)? = nil,
        struckKeys: Set<String> = [],
        onToggleStrike: ((UUID) -> Void)? = nil,
        showsCategoryFilter: Bool = false
    ) {
        self._names = names
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.initialSortMode = initialSortMode
        self._sortMode = State(initialValue: initialSortMode)
        self.onBlock = onBlock
        self.struckKeys = struckKeys
        self.onToggleStrike = onToggleStrike
        self.showsCategoryFilter = showsCategoryFilter
    }

    func isStruck(_ item: AIExtractedName) -> Bool {
        onToggleStrike != nil && struckKeys.contains(item.original.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var struckCount: Int {
        onToggleStrike == nil ? 0 : names.filter { isStruck($0) }.count
    }

    /// Nhóm lọc có hiệu lực: nhóm đã chọn không còn mục nào (bỏ / chặn hết) ⇒ về Tất cả. Xét trên **cả** `names`, không
    /// theo ô tìm.
    var activeCategoryFilter: LocalNameFilter.Category? {
        guard showsCategoryFilter, let categoryFilter,
              names.contains(where: { LocalNameFilterCategoryBadge.category(forLabel: $0.category) == categoryFilter })
        else { return nil }
        return categoryFilter
    }

    /// Nền thẻ — cũng là nền đặc của khối đầu dính (`stickyHeader`), để hai lớp liền một màu.
    static var cardBackground: Color { Color(UIColor.secondarySystemBackground) }

    public var body: some View {
        let activeFilter = activeCategoryFilter
        // Một tập cho cả ba chỗ: hàng nào hiện, dòng "Không có name khớp", "Chọn hết" / "Bỏ chọn".
        let visible = visibleNameIDs(activeFilter: activeFilter)
        // Danh sách tên riêng. `LazyVStack`: mỗi lần chọn/bỏ chọn (hay sửa nghĩa) `names` đổi, `VStack` thường
        // cập nhật lại MỌI hàng — vài trăm tên là giật; lazy chỉ dựng hàng đang hiện. `pinnedViews` ghim khối đầu (L14).
        LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
            Section {
                if let visible, visible.isEmpty {
                    noMatchRow
                }

                ForEach($names) { $item in
                    // Ô tìm / chip loại chỉ ẩn hàng; vẫn duyệt cả `$names` (không lọc mảng binding: xoá mục lúc đang lọc
                    // là binding lệch chỉ số).
                    if visible?.contains(item.id) ?? true {
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
                            // Hàng gạch (luồng AI) không chọn được ⇒ không bao giờ được lưu.
                            .disabled(isStruck(item))
                            .opacity(isStruck(item) ? 0.35 : 1)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    // Cỡ chữ theo hàng VP/Name (`DictionaryEntryRow`): tên `.headline`, nghĩa `.subheadline`.
                                    Text(item.original)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .strikethrough(isStruck(item))
                                        .lineLimit(2)

                                    ReaderAINameReviewBadges(item: item, colorsCategory: showsCategoryFilter)
                                }

                                Text(item.suggestedMeaning)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .strikethrough(isStruck(item))
                                    .lineLimit(1)
                            }
                            .opacity(isStruck(item) ? 0.45 : 1)
                            // Thân hàng (chữ + khoảng trống tới ✕) mở màn Sửa từ — như `DictionaryEntryRow`, không bọc cả
                            // hàng trong `Button`. Chọn/bỏ chọn chỉ còn ở ô vuông bên trái.
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Hàng gạch: bỏ gạch trước rồi mới sửa được.
                                guard !isStruck(item) else { return }
                                onEdit?(item.id)
                            }

                            // Nút xóa từng mục; luồng lọc local (`onBlock`) ⇒ menu hai lựa chọn.
                            removeControl(id: item.id, term: item.original, struck: isStruck(item))
                        }
                        // Không đệm hai bên: khung 44 pt của ô chọn (trái) và ✕ (phải) đã tự chừa lề, hai icon cách mép đều nhau.
                        .padding(.vertical, 4)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(8)
                        .accessibilityAction(named: "Sửa") {
                            guard !isStruck(item) else { return }
                            onEdit?(item.id)
                        }
                    }
                }
            } header: {
                stickyHeader(visible: visible, activeFilter: activeFilter)
            }
        }
        // Lề trên của thẻ nằm trong khối đầu (`stickyHeader`) để lúc dính dải đệm phía trên cũng có nền đặc.
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(Self.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            applySorting()
        }
    }

    /// Khối đầu dính (L14): đầu thẻ + ô tìm + hàng chip loại (chỉ luồng lọc local; luồng AI chỉ đầu thẻ + ô tìm). Nền đặc
    /// tô **sau** đệm nên phủ cả dải 12 pt phía trên lẫn khoảng dưới hàng chip — hàng cuộn qua không lộ chữ.
    private func stickyHeader(visible: Set<UUID>?, activeFilter: LocalNameFilter.Category?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(Color(red: 90/255.0, green: 170/255.0, blue: 255/255.0))
                    Text("Tên riêng (\(names.count))")
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if struckCount > 0 {
                        Text("· đã gạch \(struckCount)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()

                sortMenu

                Button(allSelected(visible: visible) ? "Bỏ chọn" : "Chọn hết") {
                    toggleSelectAll()
                }
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .disabled(visible?.isEmpty == true)
            }
            .padding(.bottom, 2)

            // Ô tìm trên hàng chip (mockup khung 2); luồng AI không có chip nên nằm ngay dưới đầu thẻ.
            searchField

            if showsCategoryFilter {
                ReaderAINameReviewCategoryBar(names: names, active: activeFilter) { categoryFilter = $0 }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        // Cộng `spacing` 6 của stack ⇒ cách hàng đầu ~10 pt như khi khối đầu còn là con của `VStack(spacing: 10)`.
        .padding(.bottom, 4)
        .background(Self.cardBackground)
    }

    /// Nút xoá (thùng rác) của một hàng. Luồng AI (`onBlock == nil`): xoá ngay như cũ. Luồng lọc local: menu "Bỏ khỏi lần này" (chỉ bỏ khỏi
    /// danh sách đang duyệt) / "Không phải name" (bỏ + thêm vào danh sách loại bỏ qua `onBlock`).
    @ViewBuilder
    private func removeControl(id: UUID, term: String, struck: Bool) -> some View {
        if let onToggleStrike {
            // Luồng AI: gạch / bỏ gạch, không xoá (anh Bửu 2026-11-27 — xoá nhầm là mất dòng trong tin AI).
            Button(action: { onToggleStrike(id) }) {
                if struck {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                } else {
                    removeIcon
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(struck ? "Hoàn tác gạch \(term)" : "Gạch \(term)")
        } else if onBlock != nil {
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
}
