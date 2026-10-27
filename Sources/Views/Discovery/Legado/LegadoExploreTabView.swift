import SwiftUI

/// Tab lưới thể loại của **nguồn Legado** trong Khám phá (spec §11): tiêu đề nhóm, ô bấm (mục có `url`, mở danh sách
/// phân trang cũ qua `onSelectGenre`) và điều khiển do nguồn khai (chọn / bật tắt / ô nhập + "Áp dụng" / nút), xếp theo
/// bố cục flex `style` (§11.7).
///
/// - Mục có kiểu lấy từ `SourceRuntime.legadoExploreItems` — lần đầu dùng bản đệm của lượt dựng danh mục (không chạy
///   JS `exploreUrl` lần hai); kéo làm mới / `java.refreshExplore()` (tín hiệu từ presenter) ⇒ chạy lại.
/// - Đổi điều khiển ⇒ ghi `infoMap` (bền ngay) ⇒ có `action` thì chạy (JS thường gọi `java.refreshExplore()`); ô nhập
///   không có `action` ⇒ "Áp dụng" tải lại danh mục để JS của nguồn đọc giá trị mới.
/// - Mọi lời gọi engine chạy ngoài main, trong ngữ cảnh có người dùng.
struct LegadoExploreTabView: View {
    let localPath: String
    let packageId: String
    let isTranslationEnabled: Bool
    let onSelectGenre: (CategoryResult) -> Void

    @State private var items: [LegadoEngineExploreItem]? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    /// Link "Mở link lỗi" của `errorMessage` — gán/xoá cùng chỗ với chữ lỗi.
    @State private var errorLink: SourceErrorLink? = nil
    @State private var openingErrorLink: SourceErrorLink? = nil
    /// Tab bị trình duyệt "Mở link lỗi" che (biến mất khi nó mở): lần xuất hiện lại kế tiếp không để `.task` tải trước
    /// khi chép cookie — `load` đang chạy sẽ nuốt lượt thử lại do `.errorLinkBrowser` gọi (`guard !isLoading`).
    @State private var skipsReappearLoad = false
    @State private var drafts: [String: String] = [:]
    @State private var busyTitle: String? = nil

    var body: some View {
        let refreshSerial = LegadoExploreRefreshSignal.shared.serial(packageId: packageId)
        ScrollView {
            VStack(spacing: 12) {
                content
            }
            .padding()
        }
        .refreshable { await load(preferCached: false) }
        .task {
            if skipsReappearLoad {
                skipsReappearLoad = false
                return
            }
            if items == nil { await load(preferCached: true) }
        }
        .onDisappear {
            if openingErrorLink != nil { skipsReappearLoad = true }
        }
        .errorLinkBrowser(link: $openingErrorLink, packageId: packageId) {
            Task { await load(preferCached: false) }
        }
        .onChange(of: refreshSerial) { _, _ in
            Task { await load(preferCached: false) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let items, !items.isEmpty {
            let categories = Self.categories(for: items)
            LegadoFlexLayout(spacing: 8, rowSpacing: 8).callAsFunction {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    cell(item, category: categories[index])
                        .legadoFlex(item.style, fullRow: Self.isFullRow(item))
                }
            }
            if isLoading {
                ProgressView().padding(.top, 12)
            }
        } else if isLoading {
            ProgressView()
                .padding(.top, 40)
        } else if let errorMessage {
            VStack(spacing: 12) {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                ErrorLinkCaption(link: errorLink)
                HStack(spacing: 10) {
                    // Cùng kiểu `.bordered` với nút "Mở link lỗi" cạnh nó (các tab Khám phá khác cũng vậy).
                    Button("Thử lại") { Task { await load(preferCached: false) } }
                        .buttonStyle(.bordered)
                    ErrorLinkButton(link: errorLink, presenting: $openingErrorLink, style: .bordered)
                }
            }
            .padding(.top, 40)
        } else if items != nil {
            Text("Nguồn truyện này không có danh sách thể loại cụ thể.")
                .foregroundColor(.secondary)
                .padding(.top, 40)
        }
    }

    @ViewBuilder
    private func cell(_ item: LegadoEngineExploreItem, category: CategoryResult?) -> some View {
        if item.isGroupHeader {
            Text(display(item.label))
                .font(.subheadline.weight(.bold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } else if item.isControl {
            LegadoExploreControlView(
                item: item,
                isBusy: busyTitle == item.title,
                draft: draftBinding(for: item),
                display: display,
                onChange: { change(item, to: $0) },
                onApply: { apply(item) },
                onPress: { press(item) }
            )
        } else if let category {
            // Giữ số ô/hàng nguồn khai; nhãn dài (thường do dịch) được 3 dòng và tự co chữ trước khi phải cắt "…".
            // `maxHeight: .infinity` ⇒ ô cao bằng hàng (`LegadoFlexLayout` lấy chiều cao ô cao nhất).
            Button(action: { onSelectGenre(category) }) {
                Text(display(item.label))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: .infinity)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
        }
    }

    // MARK: - Dữ liệu

    private func load(preferCached: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let loaded = try await SourceRuntime.shared.legadoExploreItems(localPath: localPath, preferCached: preferCached)
            items = loaded
            errorMessage = nil
            errorLink = nil
        } catch is CancellationError {
            // Rời màn giữa chừng.
        } catch {
            errorMessage = "Không tải được danh mục khám phá: \(error.localizedDescription)"
            // URL request lỗi lấy từ `LegadoEngineError`; không có thì trang chủ nguồn.
            errorLink = SourceErrorLink.resolve(from: error, fallback: ExtensionHostResolver.sourceUrl(packageId: packageId))
            if items?.isEmpty ?? true { items = nil }
        }
        isLoading = false
    }

    /// `select`/`toggle` đổi giá trị: ghi `infoMap` rồi chạy `action` (nếu có).
    private func change(_ item: LegadoEngineExploreItem, to value: String) {
        guard busyTitle == nil else { return }
        updateLocalValue(value, forTitle: item.title)
        commit(value, item: item, reloadWithoutAction: false)
    }

    /// Ô nhập: "Áp dụng" ⇒ ghi `infoMap`; không có `action` ⇒ tải lại danh mục.
    private func apply(_ item: LegadoEngineExploreItem) {
        guard busyTitle == nil else { return }
        let value = drafts[item.title] ?? item.value ?? ""
        updateLocalValue(value, forTitle: item.title)
        commit(value, item: item, reloadWithoutAction: true)
    }

    /// Nút: ghi trước nội dung các ô nhập chưa "Áp dụng" (nút của nguồn thường đọc thẳng `infoMap[ô nhập]`), rồi chạy
    /// `action`.
    private func press(_ item: LegadoEngineExploreItem) {
        guard let action = item.action, !action.isEmpty, busyTitle == nil else { return }
        busyTitle = item.title
        let pending = pendingDrafts()
        let path = localPath
        Task { @MainActor in
            for (title, value) in pending {
                try? await SourceRuntime.shared.setLegadoExploreValue(value, forTitle: title, localPath: path)
                updateLocalValue(value, forTitle: title)
            }
            await runAction(action)
            busyTitle = nil
        }
    }

    /// Ô nhập có nội dung khác giá trị đã ghi.
    private func pendingDrafts() -> [(String, String)] {
        guard let items else { return [] }
        return items.compactMap { item in
            guard item.kind == .text, let draft = drafts[item.title], draft != (item.value ?? "") else { return nil }
            return (item.title, draft)
        }
    }

    private func commit(_ value: String, item: LegadoEngineExploreItem, reloadWithoutAction: Bool) {
        guard busyTitle == nil else { return }
        busyTitle = item.title
        let path = localPath
        Task { @MainActor in
            defer { busyTitle = nil }
            do {
                try await SourceRuntime.shared.setLegadoExploreValue(value, forTitle: item.title, localPath: path)
            } catch {
                ToastManager.shared.show(message: "Lỗi: \(error.localizedDescription)", type: .error)
                return
            }
            if let action = item.action, !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await runAction(action)
            } else if reloadWithoutAction {
                busyTitle = nil
                await load(preferCached: false)
            }
        }
    }

    private func runAction(_ action: String) async {
        do {
            if let error = try await SourceRuntime.shared.runLegadoExploreAction(action, localPath: localPath) {
                ToastManager.shared.show(message: "Lỗi: \(error)", type: .error)
            }
        } catch is CancellationError {
            return
        } catch {
            ToastManager.shared.show(message: "Lỗi: \(error.localizedDescription)", type: .error)
        }
    }

    private func updateLocalValue(_ value: String, forTitle title: String) {
        guard var current = items else { return }
        for index in current.indices where current[index].isControl && current[index].title == title {
            current[index].value = value
        }
        items = current
    }

    private func draftBinding(for item: LegadoEngineExploreItem) -> Binding<String> {
        Binding(
            get: { drafts[item.title] ?? item.value ?? "" },
            set: { drafts[item.title] = $0 }
        )
    }

    private func display(_ text: String) -> String {
        guard isTranslationEnabled, TranslateUtils.containsChinese(text) else { return text }
        return TranslateUtils.translateMeta(text)
    }

    // MARK: - Ánh xạ

    /// Tiêu đề nhóm luôn trọn hàng; ô nhập không khai `flexBasisPercent` cũng trọn hàng (cần chỗ cho nút "Áp dụng").
    private static func isFullRow(_ item: LegadoEngineExploreItem) -> Bool {
        if item.isGroupHeader { return true }
        return item.kind == .text && item.style.flexBasisPercent == nil
    }

    /// `CategoryResult` của từng ô bấm (theo vị trí) — cùng quy tắc với danh mục `genre`: tiêu đề rỗng ⇒ "Mục N", tiêu
    /// đề trùng ⇒ thêm tên nhóm phía trước.
    private static func categories(for items: [LegadoEngineExploreItem]) -> [CategoryResult?] {
        var counts: [String: Int] = [:]
        for item in items where !item.isGroupHeader && !item.isControl {
            counts[item.title.trimmingCharacters(in: .whitespacesAndNewlines), default: 0] += 1
        }
        var output: [CategoryResult?] = []
        var group = ""
        var linkCount = 0
        for item in items {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isControl, let url = item.url,
                  !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if item.isGroupHeader, !title.isEmpty { group = title }
                output.append(nil)
                continue
            }
            linkCount += 1
            var name = title.isEmpty ? "Mục \(linkCount)" : title
            if (counts[title] ?? 0) > 1, !group.isEmpty { name = group + " · " + name }
            output.append(CategoryResult(title: name, input: url, script: SourceRuntime.legadoExploreScriptName))
        }
        return output
    }
}
