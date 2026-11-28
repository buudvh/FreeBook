import SwiftUI

/// Trang **Lịch sử lọc** của Lọc name local (anh Bửu duyệt mockup + plan "Lịch sử lọc — H1–H5",
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2) — đẩy vào `NavigationStack` của sheet từ hàng "Lịch sử lọc" (H1,
/// `LocalNameFilterSheet+History`).
///
/// - **H2**: nhóm theo ngày ("Hôm nay · 28/11", "27/11"…), mới nhất trên cùng, không giới hạn số lần; hàng
///   `LocalNameFilterHistoryRow`. Chạm lần chưa lưu còn gói ⇒ `onOpenDraft` (sheet mở lại màn duyệt như chạm gói tạm
///   trước đây — `LocalNameFilterSession.openDraft`); lần đã lưu chỉ xem; gói đã bị xoá ⇒ mờ, không mở được. Lần không ra
///   màn duyệt (bản 8: không ra name nào, lỗi, đã huỷ, bị ngắt) ⇒ nền sẫm, chạm không mở gì, vẫn xoá / chọn nhiều được,
///   tính vào "N lần" (không vào "M chưa lưu"). Vuốt trái ⇒ Xoá.
/// - **H3 / H4 / H5** (`+Delete`): mọi lối xoá đều hỏi lại; ⋯ mở ngăn kéo "Chọn nhiều để xoá" / "Dọn dẹp tất cả"; chế độ
///   chọn nhiều kiểu Kệ (header ✕ + "Đã chọn N" + "Chọn tất cả", chạm hàng để tích, thanh đáy "Xoá (N)").
///
/// Mỗi lần trang hiện ra: đọc lịch sử + gói tạm (`LocalNameFilterHistoryStore.snapshot` — gói chưa có mục được tạo mục
/// "chưa lưu"), rồi cho gói tạm tự cập nhật theo "Không phải name" + danh sách hậu tố / tiền tố như trước
/// (`LocalNameFilterDraftRefresher`). Store không phát thay đổi ⇒ trang giữ bản chụp ở `@State`, sửa tại chỗ sau mỗi lần xoá.
struct LocalNameFilterHistoryView: View {
    /// Một nhóm ngày của danh sách (giữ thứ tự mới nhất trước).
    struct DayGroup: Identifiable {
        let id: DateComponents
        let title: String
        var entries: [LocalNameFilterHistoryEntry]
    }

    static let title = "Lịch sử lọc"

    static var helpParagraphs: [LocalizedStringKey] {
        [
            "Mỗi lần bấm \"Bắt đầu lọc\" ghi một dòng: giờ bắt đầu · phạm vi chương đã đọc (bấm \"Dừng\" thì là các chương đã lọc tới, kèm \"(dừng)\"). Lịch sử không giới hạn, mới nhất trên cùng.",
            "Lần **không ra màn duyệt** có nền sẫm, chạm không mở gì: không ra name nào, lỗi (kèm lý do), đã huỷ (đóng sheet lúc đang lọc — phạm vi là các chương đã đọc tới, kèm \"(huỷ)\"), bị ngắt (app thoát lúc đang lọc).",
            "**Chưa lưu**: đóng màn duyệt mà chưa bấm Lưu (kể cả sau \"Dừng\") thì danh sách đang duyệt được giữ thành gói tạm, gồm cả ô đã chọn / bỏ chọn và nghĩa đã sửa — chạm dòng để mở lại đúng màn duyệt đó. Mỗi truyện giữ \(LocalNameFilterDraftStore.maxDraftsPerBook) gói ghi gần nhất; gói cũ hơn bị xoá, dòng của nó mờ đi.",
            "Gói tự cập nhật mỗi lần mở trang: name nằm trong \"Không phải name\" bị bỏ; name còn nghĩa máy ghép (trừ họ tộc) thì ghép lại theo danh sách hậu tố / tiền tố hiện tại. Nghĩa đã tự sửa giữ nguyên.",
            "**Đã lưu X / Y**: đã lưu X trong Y name lọc được — dòng này chỉ để xem. Xoá một lần lọc (vuốt trái, hoặc ⋯ › Chọn nhiều để xoá) xoá luôn gói tạm chưa lưu của lần đó; name đã lưu vào Name / VP riêng giữ nguyên."
        ]
    }

    let bookId: String
    /// Chạm lần lọc chưa lưu còn gói tạm ⇒ sheet mở lại màn duyệt của gói đó.
    let onOpenDraft: (LocalNameFilterDraft) -> Void

    @Environment(\.isGlassSheet) private var isGlassSheet
    @State var snapshot = LocalNameFilterHistorySnapshot.empty
    @State var isLoaded = false
    @State var showingMenu = false
    /// Đang chọn nhiều để xoá (H5): các lần đã tích; `nil` = không ở chế độ chọn.
    @State var selection: Set<UUID>? = nil
    /// Lối xoá đang chờ hỏi lại (H3 / H4 / H5).
    @State var deleteRequest: DeleteRequest? = nil

    var isSelecting: Bool { selection != nil }

    var body: some View {
        list
            // Một modifier cho cả hai chế độ (chỉ tham số đổi) ⇒ vào / ra chế độ chọn không dựng lại trang, giữ vị trí cuộn.
            .pageTitle(
                selection.map { "Đã chọn \(selectedIds($0).count)" } ?? Self.title,
                style: isSelecting ? .leading : .centered,
                leadingIcon: isSelecting ? selectionExitButton : nil
            )
            .navigationBarBackButtonHidden(isSelecting)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    headerTrailingButton
                }
            }
            // Inset luôn gắn, chỉ nội dung đổi (như thanh chọn của Kệ) — đổi cấu trúc là trang dựng lại.
            .safeAreaInset(edge: .bottom) { selectionBar }
            .sideDrawerMenu(isPresented: $showingMenu, title: "\(Self.title) · \(snapshot.entries.count) lần") {
                drawerContent
            }
            .alert(
                deleteRequest?.title ?? "",
                isPresented: Binding(
                    get: { deleteRequest != nil },
                    set: { presented in
                        if !presented { deleteRequest = nil }
                    }
                ),
                presenting: deleteRequest
            ) { request in
                Button("Huỷ", role: .cancel) {}
                Button("Xoá", role: .destructive) { performDelete(request) }
            } message: { request in
                Text(request.message)
            }
            .task { await load() }
    }

    private var list: some View {
        List { Group {
            if isLoaded && snapshot.isEmpty {
                Section {
                    Text("Chưa có lần lọc nào. Mỗi lần bấm \"Bắt đầu lọc\" sẽ ghi một dòng ở đây.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    SectionHelpHeader(Self.title, paragraphs: Self.helpParagraphs)
                }
            }
            ForEach(Array(dayGroups.enumerated()), id: \.element.id) { index, group in
                Section {
                    ForEach(group.entries) { entry in
                        row(entry)
                    }
                } header: {
                    if index == 0 {
                        SectionHelpHeader(group.title, paragraphs: Self.helpParagraphs)
                    } else {
                        Text(verbatim: group.title)
                    }
                }
            }
        }.glassSheetRows() }
        .listStyle(.insetGrouped)
    }

    private func row(_ entry: LocalNameFilterHistoryEntry) -> some View {
        let status = snapshot.status(of: entry)
        let isOpenable: Bool = {
            if case .unsaved = status { return true }
            return false
        }()
        return LocalNameFilterHistoryRow(
            entry: entry,
            status: status,
            isSelecting: isSelecting,
            isSelected: selection?.contains(entry.id) == true
        )
        // Lần không ra màn duyệt (không ra name, lỗi, huỷ, bị ngắt): nền sẫm (mockup H2 bản 8). Ô tự đặt nền thắng ô mờ
        // `glassSheetRows` của cả danh sách ⇒ hàng thường đặt lại đúng ô mờ đó.
        .listRowBackground(rowBackground(for: status))
        // Không bọc cả hàng trong `Button` (luật màn danh sách) — chạm thân hàng.
        .contentShape(Rectangle())
        .onTapGesture { tap(entry, status: status) }
        .accessibilityAddTraits(isSelecting || isOpenable ? .isButton : [])
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isSelecting {
                // Không dùng `role: .destructive`: List sẽ cho hàng trượt mất trước khi hỏi lại.
                Button {
                    requestDelete(entry)
                } label: {
                    Text("Xoá")
                }
                .tint(.red)
            }
        }
    }

    private func rowBackground(for status: LocalNameFilterHistorySnapshot.Status) -> Color? {
        if status.isInactive { return LocalNameFilterHistoryRow.inactiveFill }
        return isGlassSheet ? AppGlassSheetModifier.rowFill : nil
    }

    /// Chọn nhiều ⇒ tích / bỏ tích (không mở gói); thường ⇒ chỉ lần chưa lưu còn gói mới mở (đã lưu, gói đã bị xoá, lần
    /// không ra màn duyệt: chạm không làm gì).
    private func tap(_ entry: LocalNameFilterHistoryEntry, status: LocalNameFilterHistorySnapshot.Status) {
        if var current = selection {
            if current.contains(entry.id) {
                current.remove(entry.id)
            } else {
                current.insert(entry.id)
            }
            selection = current
            return
        }
        if case .unsaved(let draft) = status {
            onOpenDraft(draft)
        }
    }

    /// Nhóm theo ngày của giờ bắt đầu; hôm nay ⇒ "Hôm nay · 28/11", ngày khác ⇒ "27/11" (khác năm ⇒ "27/11/2025").
    var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        var groups: [DayGroup] = []
        for entry in snapshot.entries {
            let day = calendar.dateComponents([.year, .month, .day], from: entry.startedAt)
            if let last = groups.indices.last, groups[last].id == day {
                groups[last].entries.append(entry)
                continue
            }
            let dayText = LocalNameFilterHistoryRow.dayText(entry.startedAt)
            let title = calendar.isDateInToday(entry.startedAt) ? "Hôm nay · \(dayText)" : dayText
            groups.append(DayGroup(id: day, title: title, entries: [entry]))
        }
        return groups
    }

    // MARK: - Nạp

    private func load() async {
        let bid = bookId
        let loaded = await Self.loadSnapshot(bookId: bid)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            snapshot = loaded
            isLoaded = true
        }
        guard !loaded.drafts.isEmpty else { return }
        let refreshed = await Self.refreshedDrafts(bookId: bid)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            snapshot = snapshot.replacingDrafts(refreshed)
        }
    }

    /// Lịch sử + gói tạm của truyện, đọc ngoài main (dùng chung với hàng "Lịch sử lọc" của sheet).
    static func loadSnapshot(bookId: String) async -> LocalNameFilterHistorySnapshot {
        await Task.detached(priority: .userInitiated) {
            LocalNameFilterHistoryStore.snapshot(bookId: bookId)
        }.value
    }

    /// Gói tạm sau khi tự cập nhật theo "Không phải name" + danh sách hậu tố / tiền tố + công tắc Latin hiện tại
    /// (`LocalNameFilterDraftRefresher`, plan 2026-11-27-nghia-ten-tay-huyen mục 6): danh sách chụp trên main, cập nhật ngoài
    /// main. Chạy lại song song vô hại (đọc – sửa – ghi trong khoá của store, dấu trùng thì không ghép lại).
    static func refreshedDrafts(bookId: String) async -> [LocalNameFilterDraft] {
        let inputs = await MainActor.run { LocalNameFilterDraftRefresher.currentInputs(bookId: bookId) }
        return await Task.detached(priority: .userInitiated) {
            await LocalNameFilterDraftRefresher.refresh(inputs)
        }.value
    }
}
