import SwiftUI

/// Sheet "Lọc name local" (Reader › "…", plan 2026-11-27, mockup khung 2–4; bản LAC: mockup LAC khung 1–5): tự dò tên
/// người / địa danh / tổ chức / thuật ngữ trong chữ Hán các chương đã tải, ngay trên máy, không gọi AI, rồi duyệt và lưu
/// vào Name / VP riêng của truyện.
///
/// Ba bước trong **một** sheet, theo `LocalNameFilterSession.phase`:
/// 1. Chọn phạm vi (`+Setup`): như "Lọc name nhiều chương" của AI (`ReaderAIBatchPromptSheet`) bỏ "Tiếp nối"; không đọc /
///    ghi mặc định của sheet AI. "Gói tạm chưa lưu" ở đầu (`+Drafts`, chỉ khi có gói), "Loại cần tìm" (`+Categories`,
///    nhớ bằng `@AppStorage`), "Ít nhất N lần" (mặc định 3) + "Ưu tiên tên Latin" (theo truyện,
///    `LocalNameFilterLatinPreferenceStore`), mục "Danh sách" mở hai màn quản lý dùng chung mọi truyện.
///    Không có hàng tải model: chưa có model thì bước 2 tự tải trước.
/// 2. Đang lọc (`LocalNameFilterProgressView`): "Tải model" (lần đầu) rồi "Phân tích chương", name hiện dần; "Dừng" =
///    phân tích nốt phần đã đọc rồi sang bước 3. Lỗi ⇒ "Quay lại" / "Thử lại" (đúng cấu hình cũ).
/// 3. Duyệt: thay cả gốc sheet bằng `ReaderAINameReviewSheet` (danh sách có sẵn, sắp "Nhiều lần nhất", chip lọc loại,
///    badge NE / VP + name đã có bỏ chọn sẵn, ✕ có "Không phải name"); lưu thẳng qua `AIHarnessService.saveExtractedEntries`
///    như màn AI.
/// Đóng sheet (vuốt xuống) ở bất kỳ bước nào ⇒ huỷ lượt lọc; đang duyệt mà chưa Lưu ⇒ giữ gói tạm + toast. `onDisappear`
/// gắn ở `ZStack` ngoài cùng, sống qua mọi lần đổi bước (gắn vào `Group` thì SwiftUI rải xuống từng nhánh, đổi bước là
/// tưởng đóng sheet). App vào nền lúc đang duyệt ⇒ cũng giữ gói (không toast).
struct LocalNameFilterSheet: View {
    /// Kiểu chọn chương bắt đầu (bỏ "Tiếp nối" của sheet AI: lọc local không lưu tiến độ).
    enum ScanStart: Hashable {
        case current, first, custom
    }

    static let minCountChoices = [2, 3, 5, 10]

    let bookId: String
    /// Chương đang đọc (0-based theo mục lục).
    let chapterIndex: Int
    /// Reader bật dịch ⇒ tên chương ở phạm vi lọc là bản dịch, như danh sách chương Reader.
    let translatesChapterTitles: Bool
    /// Cờ phồn → giản của Reader — chữ đưa vào bộ lọc là chữ Reader đang hiện.
    let convertsTraditionalToSimplified: Bool

    @Environment(\.scenePhase) private var scenePhase
    /// `false` khi sheet đang đóng thật; vẫn `true` lúc chỉ bị màn toàn màn che (xem `closeSheet`).
    @Environment(\.isPresented) private var isPresented
    @State var session = LocalNameFilterSession()
    /// Kiểu người dùng đã bấm; `nil` = theo `defaultStart` (chỉ chốt được sau khi nạp xong danh sách chương).
    @State var pickedStart: ScanStart? = nil
    /// Chương tự chọn ở "Chọn chương…" — không nhớ giữa các lần mở sheet.
    @State var customChapterIndex: Int? = nil
    /// "Số lượng chương" — mỗi lần mở về Tất cả như sheet AI.
    @State var limitOption: ChapterLimitOption = .all
    @State var customLimit: Int = 100
    /// Chương đã tải theo thứ tự mục lục, nạp một lần khi mở sheet; `nil` = đang nạp.
    @State var chapters: [AINameScanChapter]? = nil
    /// "Ít nhất N lần" — mặc định 3, không nhớ giữa các lần mở.
    @State var minCount: Int = 3
    /// "Ưu tiên tên Latin" của truyện này — đọc khi mở / quay về, ghi ngay khi bấm (`LocalNameFilterLatinPreferenceStore`).
    @State var prefersLatinNames: Bool = false
    /// Số đuôi trong danh sách / số cụm "Không phải name" — đọc lại mỗi khi quay về từ màn quản lý.
    @State var suffixCount: Int = 0
    @State var blockedCount: Int = 0
    /// "Loại cần tìm" (`+Categories`): `rawValue` các nhóm nối bằng dấu phẩy; rỗng / hỏng = cả bốn nhóm.
    @AppStorage("localNameFilterCategories") var categoriesRaw: String = ""
    /// Gói tạm chưa lưu của truyện (`+Drafts`), ghi gần nhất trước; nạp ngoài main khi mở sheet.
    @State var drafts: [LocalNameFilterDraft] = []

    var body: some View {
        ZStack {
            if session.phase == .review {
                ReaderAINameReviewSheet(
                    names: session.reviewNames,
                    bookId: bookId,
                    onSave: { items, isName, isMerge in save(items, isName: isName, isMerge: isMerge) },
                    onBlockName: { item in block(item) },
                    onNamesChange: { names in session.updateReviewNames(names) }
                )
            } else {
                NavigationStack {
                    phaseContent
                        .pageTitle("Lọc name local")
                        .safeAreaInset(edge: .bottom) { bottomBar }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onDisappear { closeSheet() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                session.persistDraftForBackground()
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch session.phase {
        case .setup, .review:
            setupForm
        case .preparing, .running, .stopping, .failed:
            LocalNameFilterProgressView(session: session)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        Group {
            switch session.phase {
            case .setup, .review:
                Button(action: startFilter) {
                    Text("Bắt đầu lọc")
                }
                .buttonStyle(.appFilled)
                .disabled(!canStart)
            case .preparing, .running:
                Button(action: { session.stop() }) {
                    Text("Dừng")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            case .stopping:
                Button(action: {}) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Đang phân tích nốt…")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            case .failed:
                HStack(spacing: 10) {
                    Button(action: { session.leaveFailure() }) {
                        Text("Quay lại")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { session.retry() }) {
                        Text("Thử lại")
                    }
                    .buttonStyle(.appFilled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Chụp cấu hình từ hai danh sách + "Loại cần tìm" đúng lúc bấm, rồi giao cho `session` (lấy chương đã tải theo phạm
    /// vi + chạy).
    private func startFilter() {
        guard canStart else { return }
        let configuration = LocalNameFilter.Configuration(
            minCount: minCount,
            suffixes: LocalNameFilterSuffixStore.shared.allSuffixes(),
            blockedTerms: LocalNameFilterBlocklistStore.shared.terms(),
            categories: selectedCategories,
            prefersLatinNames: prefersLatinNames
        )
        let numbers = Dictionary((chapters ?? []).map { ($0.index, $0.number) }, uniquingKeysWith: { first, _ in first })
        session.start(LocalNameFilterSession.StartRequest(
            bookId: bookId,
            fromChapterIndex: fromChapterIndexForRun,
            limit: limitValue,
            convertsTraditional: convertsTraditionalToSimplified,
            configuration: configuration,
            chapterNumbers: numbers
        ))
    }

    /// Sheet đóng (vuốt xuống, hoặc màn duyệt tự đóng sau khi bấm Lưu): đang duyệt mà chưa Lưu ⇒ giữ gói tạm; rồi huỷ
    /// lượt lọc nếu còn chạy.
    ///
    /// `onDisappear` còn chạy khi sheet chỉ bị **che** (màn Sửa từ mở tra cứu ngoài bằng `fullScreenCover`) — lúc đó vẫn
    /// ghi gói (ghi đè cùng gói, vô hại) và `cancel()` vô hại ở màn duyệt, nhưng chỉ báo toast khi sheet thật sự đóng
    /// (`isPresented == false`), để không báo sớm rồi báo lại lần hai.
    private func closeSheet() {
        if let kept = session.keepDraftOnClose(), !isPresented {
            ToastManager.shared.show(message: "Đã giữ gói tạm (\(kept) name)", type: .info)
        }
        session.cancel()
    }

    /// Lưu như màn AI (Name riêng / VP riêng, Gộp / Thay thế) — `ReaderAINameReviewSheet` đóng sheet ngay sau khi gọi.
    /// Lưu xong ⇒ xoá gói tạm của màn duyệt này (mở từ gói, hoặc đã ghi khi app vào nền); lưu lỗi ⇒ ghi gói để không mất
    /// danh sách.
    private func save(_ items: [AIExtractedName], isName: Bool, isMerge: Bool) {
        let bid = bookId
        let pending = session.beginSave()
        Task {
            let savedCount = await AIHarnessService.shared.saveExtractedEntries(
                items, bookId: bid, isName: isName, isMerge: isMerge
            )
            await MainActor.run {
                let targetName = isName ? "Name riêng" : "VietPhrase riêng"
                if savedCount > 0 {
                    if let pending {
                        LocalNameFilterDraftStore.delete(id: pending.draft.id, bookId: pending.bookId)
                    }
                    ToastManager.shared.show(message: "Đã lưu \(savedCount) mục vào \(targetName) của truyện", type: .success)
                } else if let pending, !pending.draft.names.isEmpty {
                    LocalNameFilterDraftStore.upsert(pending.draft, bookId: pending.bookId)
                    ToastManager.shared.show(
                        message: "Lưu vào \(targetName) thất bại · đã giữ gói tạm (\(pending.draft.names.count) name)",
                        type: .error
                    )
                } else {
                    ToastManager.shared.show(message: "Lưu vào \(targetName) thất bại", type: .error)
                }
            }
        }
    }

    /// ✕ › "Không phải name": màn duyệt bỏ mục khỏi lần này; ở đây thêm vào danh sách loại bỏ dùng chung. Store từ chối
    /// (không phải chữ Hán, quá dài, đầy danh sách…) ⇒ toast lỗi của store, mục vẫn chỉ bị bỏ khỏi lần này.
    private func block(_ item: AIExtractedName) {
        let term = item.original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        if let error = LocalNameFilterBlocklistStore.shared.add(term) {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            ToastManager.shared.show(message: "Đã thêm \(term) vào “Không phải name”", type: .success)
        }
    }
}
